import { createHash, randomBytes, randomUUID } from 'node:crypto';
import { SignJWT, jwtVerify } from 'jose';
import type { Db } from '../db.js';
import { unauthorized } from '../errors.js';

export const ACCESS_TTL_SEC = 60 * 60; // 1시간
export const REFRESH_TTL_MS = 30 * 24 * 60 * 60 * 1000; // 30일

export interface TokenPair {
  accessToken: string;
  refreshToken: string;
  accessExpiresIn: number;
}

const hash = (token: string) => createHash('sha256').update(token).digest('hex');

export class TokenService {
  private readonly key: Uint8Array;

  constructor(
    private readonly db: Db,
    secret: string,
    private readonly now: () => Date = () => new Date(),
  ) {
    this.key = new TextEncoder().encode(secret);
  }

  async signAccess(userId: string): Promise<string> {
    const iat = Math.floor(this.now().getTime() / 1000);
    return new SignJWT({})
      .setProtectedHeader({ alg: 'HS256' })
      .setSubject(userId)
      .setIssuedAt(iat)
      .setExpirationTime(iat + ACCESS_TTL_SEC)
      .setIssuer('meeil')
      .sign(this.key);
  }

  async verifyAccess(token: string): Promise<string> {
    try {
      const { payload } = await jwtVerify(token, this.key, {
        issuer: 'meeil',
        algorithms: ['HS256'],
        currentDate: this.now(),
      });
      if (!payload.sub) throw unauthorized();
      return payload.sub;
    } catch {
      throw unauthorized();
    }
  }

  /** 새 로그인: 새 refresh 토큰 계열(family)을 시작한다. */
  async issue(userId: string, familyId: string = randomUUID()): Promise<TokenPair> {
    const refreshToken = randomBytes(32).toString('base64url');
    await this.db.refreshToken.create({
      data: {
        userId,
        familyId,
        tokenHash: hash(refreshToken),
        expiresAt: new Date(this.now().getTime() + REFRESH_TTL_MS),
      },
    });
    return {
      accessToken: await this.signAccess(userId),
      refreshToken,
      accessExpiresIn: ACCESS_TTL_SEC,
    };
  }

  /**
   * refresh 회전. 이미 사용(폐기)된 토큰이 다시 오면 탈취로 보고 계열 전체를 폐기한다.
   */
  async rotate(refreshToken: string): Promise<{ userId: string; tokens: TokenPair }> {
    const row = await this.db.refreshToken.findUnique({ where: { tokenHash: hash(refreshToken) } });
    if (!row) throw unauthorized();
    if (row.revokedAt) {
      await this.revokeFamily(row.familyId);
      throw unauthorized();
    }
    if (row.expiresAt <= this.now()) throw unauthorized();
    // 동시 요청 경합: 조건부 업데이트로 한 번만 회전되게 한다
    const { count } = await this.db.refreshToken.updateMany({
      where: { id: row.id, revokedAt: null },
      data: { revokedAt: this.now() },
    });
    if (count === 0) {
      await this.revokeFamily(row.familyId);
      throw unauthorized();
    }
    return { userId: row.userId, tokens: await this.issue(row.userId, row.familyId) };
  }

  async revoke(refreshToken: string): Promise<void> {
    const row = await this.db.refreshToken.findUnique({ where: { tokenHash: hash(refreshToken) } });
    if (row) await this.revokeFamily(row.familyId);
  }

  private async revokeFamily(familyId: string): Promise<void> {
    await this.db.refreshToken.updateMany({
      where: { familyId, revokedAt: null },
      data: { revokedAt: this.now() },
    });
  }
}
