// 사진 저장소. 객체는 비공개이고, 밖으로는 짧게 유효한 서명 URL만 준다(CLAUDE.md 규칙).
import { createHmac, timingSafeEqual } from 'node:crypto';
import { mkdir, readFile, rm, writeFile } from 'node:fs/promises';
import { dirname, join, resolve } from 'node:path';
import {
  DeleteObjectCommand,
  GetObjectCommand,
  PutObjectCommand,
  S3Client,
} from '@aws-sdk/client-s3';
import { getSignedUrl } from '@aws-sdk/s3-request-presigner';

export interface Storage {
  put(key: string, body: Buffer, contentType: string): Promise<void>;
  delete(key: string): Promise<void>;
  /** 읽기 전용 서명 URL */
  signedUrl(key: string, ttlSec?: number): Promise<string>;
}

export const DEFAULT_URL_TTL_SEC = 15 * 60;

const KEY_RE = /^[a-zA-Z0-9/_.-]{1,200}$/;
function checkKey(key: string): void {
  if (!KEY_RE.test(key) || key.includes('..')) throw new Error(`잘못된 저장 키: ${key}`);
}

/** 개발·테스트용: 디스크에 저장하고, 이 서버의 /media 경로로 HMAC 서명 URL을 준다 */
export class LocalStorage implements Storage {
  private readonly root: string;

  constructor(
    dir: string,
    private readonly baseUrl: string,
    private readonly secret: string,
    private readonly now: () => Date = () => new Date(),
  ) {
    this.root = resolve(dir);
  }

  private path(key: string): string {
    checkKey(key);
    return join(this.root, key);
  }

  async put(key: string, body: Buffer): Promise<void> {
    const p = this.path(key);
    await mkdir(dirname(p), { recursive: true });
    await writeFile(p, body);
  }

  async delete(key: string): Promise<void> {
    await rm(this.path(key), { force: true });
  }

  async read(key: string): Promise<Buffer> {
    return readFile(this.path(key));
  }

  sign(key: string, exp: number): string {
    return createHmac('sha256', this.secret).update(`${key}:${exp}`).digest('base64url');
  }

  /** /media/<key>?exp=..&sig=.. 검증 */
  verify(key: string, exp: number, sig: string): boolean {
    if (!Number.isFinite(exp) || exp * 1000 < this.now().getTime()) return false;
    const expected = Buffer.from(this.sign(key, exp));
    const given = Buffer.from(sig);
    return expected.length === given.length && timingSafeEqual(expected, given);
  }

  async signedUrl(key: string, ttlSec = DEFAULT_URL_TTL_SEC): Promise<string> {
    checkKey(key);
    const exp = Math.floor(this.now().getTime() / 1000) + ttlSec;
    return `${this.baseUrl}/media/${key}?exp=${exp}&sig=${this.sign(key, exp)}`;
  }
}

/** 운영: Cloudflare R2(S3 호환) 비공개 버킷 + presigned GET */
export class R2Storage implements Storage {
  private readonly s3: S3Client;

  constructor(
    accountId: string,
    accessKeyId: string,
    secretAccessKey: string,
    private readonly bucket: string,
  ) {
    this.s3 = new S3Client({
      region: 'auto',
      endpoint: `https://${accountId}.r2.cloudflarestorage.com`,
      credentials: { accessKeyId, secretAccessKey },
    });
  }

  async put(key: string, body: Buffer, contentType: string): Promise<void> {
    checkKey(key);
    await this.s3.send(
      new PutObjectCommand({ Bucket: this.bucket, Key: key, Body: body, ContentType: contentType }),
    );
  }

  async delete(key: string): Promise<void> {
    await this.s3.send(new DeleteObjectCommand({ Bucket: this.bucket, Key: key }));
  }

  async signedUrl(key: string, ttlSec = DEFAULT_URL_TTL_SEC): Promise<string> {
    return getSignedUrl(this.s3, new GetObjectCommand({ Bucket: this.bucket, Key: key }), {
      expiresIn: ttlSec,
    });
  }
}
