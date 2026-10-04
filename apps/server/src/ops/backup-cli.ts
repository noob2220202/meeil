// 백업 보관소 CLI (docs/OPERATIONS.md). api 컨테이너 안에서 돌려 서버 의존성(S3 SDK)을 그대로 쓴다.
//   put <key>      표준 입력 → 보관소
//   get <key>      보관소 → 표준 출력
//   latest         가장 최근 백업 키 출력
//   list           백업 키 목록
//   prune [--dry]  보관 규칙(30일 매일 + 12개월 월초)에 따라 지운다
// 보관소: BACKUP_DIR이 있으면 로컬 폴더(리허설·개발), 없으면 R2_BACKUP_BUCKET(비공개 버킷).
import {
  DeleteObjectCommand,
  GetObjectCommand,
  ListObjectsV2Command,
  PutObjectCommand,
  S3Client,
} from '@aws-sdk/client-s3';
import { mkdir, readdir, readFile, rm, writeFile } from 'node:fs/promises';
import { dirname, join, relative, resolve } from 'node:path';
import { expiredBackups, parseBackupKey } from './retention.js';

export interface BackupStore {
  put(key: string, body: Buffer): Promise<void>;
  get(key: string): Promise<Buffer>;
  list(): Promise<string[]>;
  delete(key: string): Promise<void>;
}

export class DirBackupStore implements BackupStore {
  constructor(private readonly root: string) {}

  private path(key: string): string {
    const p = resolve(this.root, key);
    if (relative(resolve(this.root), p).startsWith('..')) throw new Error(`잘못된 키: ${key}`);
    return p;
  }

  async put(key: string, body: Buffer) {
    await mkdir(dirname(this.path(key)), { recursive: true });
    await writeFile(this.path(key), body);
  }

  get(key: string) {
    return readFile(this.path(key));
  }

  async list() {
    try {
      return (await readdir(join(this.root, 'db'))).map((f) => `db/${f}`);
    } catch {
      return [];
    }
  }

  async delete(key: string) {
    await rm(this.path(key), { force: true });
  }
}

export class R2BackupStore implements BackupStore {
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

  async put(key: string, body: Buffer) {
    await this.s3.send(
      new PutObjectCommand({
        Bucket: this.bucket,
        Key: key,
        Body: body,
        ContentType: 'application/octet-stream',
      }),
    );
  }

  async get(key: string) {
    const r = await this.s3.send(new GetObjectCommand({ Bucket: this.bucket, Key: key }));
    return Buffer.from(await r.Body!.transformToByteArray());
  }

  async list() {
    const keys: string[] = [];
    let token: string | undefined;
    do {
      const r = await this.s3.send(
        new ListObjectsV2Command({ Bucket: this.bucket, Prefix: 'db/', ContinuationToken: token }),
      );
      for (const o of r.Contents ?? []) if (o.Key) keys.push(o.Key);
      token = r.IsTruncated ? r.NextContinuationToken : undefined;
    } while (token);
    return keys;
  }

  async delete(key: string) {
    await this.s3.send(new DeleteObjectCommand({ Bucket: this.bucket, Key: key }));
  }
}

export function storeFromEnv(env: NodeJS.ProcessEnv = process.env): BackupStore {
  if (env.BACKUP_DIR) return new DirBackupStore(env.BACKUP_DIR);
  const need = ['R2_ACCOUNT_ID', 'R2_ACCESS_KEY_ID', 'R2_SECRET_ACCESS_KEY', 'R2_BACKUP_BUCKET'];
  const missing = need.filter((k) => !env[k]);
  if (missing.length > 0) throw new Error(`백업 보관소 설정이 없어요: ${missing.join(', ')}`);
  if (env.R2_BACKUP_BUCKET === env.R2_BUCKET) {
    // 사진 버킷과 섞으면 사진 정리 작업·권한이 백업에 닿는다
    throw new Error('R2_BACKUP_BUCKET은 사진 버킷(R2_BUCKET)과 달라야 해요.');
  }
  return new R2BackupStore(
    env.R2_ACCOUNT_ID!,
    env.R2_ACCESS_KEY_ID!,
    env.R2_SECRET_ACCESS_KEY!,
    env.R2_BACKUP_BUCKET!,
  );
}

async function readStdin(): Promise<Buffer> {
  const chunks: Buffer[] = [];
  for await (const c of process.stdin) chunks.push(c as Buffer);
  return Buffer.concat(chunks);
}

export async function latestBackup(store: BackupStore): Promise<string | null> {
  const keys = (await store.list()).filter((k) => parseBackupKey(k));
  keys.sort((a, b) => parseBackupKey(a)!.getTime() - parseBackupKey(b)!.getTime());
  return keys[keys.length - 1] ?? null;
}

async function main(argv: string[]) {
  const [cmd, arg] = argv;
  const store = storeFromEnv();
  const keyArg = () => {
    if (!arg || !parseBackupKey(arg)) throw new Error(`백업 키 형식이 아니에요: ${arg ?? ''}`);
    return arg;
  };
  switch (cmd) {
    case 'put': {
      const body = await readStdin();
      if (body.length < 1024) throw new Error(`백업이 너무 작아요(${body.length}B). 덤프 실패?`);
      await store.put(keyArg(), body);
      console.error(`올림 ${arg} (${(body.length / 1024 / 1024).toFixed(2)} MiB)`);
      return;
    }
    case 'get':
      process.stdout.write(await store.get(keyArg()));
      return;
    case 'latest': {
      const k = await latestBackup(store);
      if (!k) throw new Error('백업이 하나도 없어요.');
      console.log(k);
      return;
    }
    case 'list':
      for (const k of (await store.list()).sort()) console.log(k);
      return;
    case 'prune': {
      const dry = argv.includes('--dry');
      const expired = expiredBackups(await store.list(), new Date());
      for (const k of expired) {
        if (!dry) await store.delete(k);
        console.error(`${dry ? '(지울 예정)' : '지움'} ${k}`);
      }
      console.error(`보관 규칙 적용: ${expired.length}개 ${dry ? '지울 예정' : '지움'}`);
      return;
    }
    default:
      console.error('사용: backup-cli <put|get> <key> | latest | list | prune [--dry]');
      process.exitCode = 2;
  }
}

if (import.meta.url === `file://${process.argv[1]}`) {
  main(process.argv.slice(2)).catch((e: unknown) => {
    console.error(`백업 오류: ${(e as Error).message}`);
    process.exit(1);
  });
}
