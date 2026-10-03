import 'dotenv/config';
import type { FastifyInstance } from 'fastify';
import { buildApp } from '../src/app.js';
import { AppError } from '../src/errors.js';
import type { SocialVerifier } from '../src/auth/social.js';
import { createDb, type Db } from '../src/db.js';
import { loadEnv } from '../src/env.js';
import { testDatabaseUrl } from './global-setup.js';

/** 테스트용 소셜 검증기: 'kakao-ok:<id>', 'google-ok:<id>' 형태만 통과 */
export const fakeSocial: SocialVerifier = {
  async kakao(token) {
    if (!token.startsWith('kakao-ok:')) throw new AppError(401, 'SOCIAL_TOKEN_INVALID', 'x');
    return { providerUserId: token.slice(9) };
  },
  async google(token) {
    if (!token.startsWith('google-ok:')) throw new AppError(401, 'SOCIAL_TOKEN_INVALID', 'x');
    return { providerUserId: token.slice(10) };
  },
};

/** 테스트에서 시각을 움직일 수 있는 시계 */
export function testClock(start = new Date('2026-10-03T03:00:00Z')) {
  let t = start.getTime();
  return {
    now: () => new Date(t),
    set: (d: Date) => (t = d.getTime()),
    advanceDays: (days: number) => (t += days * 24 * 60 * 60 * 1000),
  };
}

/** 실제 PostgreSQL(DATABASE_URL)에 붙는 통합 테스트용 앱 */
export async function createTestApp(
  opts: { now?: () => Date; devLogin?: boolean; rateLimit?: boolean } = {},
): Promise<{ app: FastifyInstance; db: Db }> {
  const env = loadEnv({
    ...process.env,
    NODE_ENV: 'test',
    DATABASE_URL: testDatabaseUrl(),
    JWT_SECRET: process.env.JWT_SECRET ?? 'test-secret-0123456789abcdef0123456789',
    AUTH_DEV_LOGIN: opts.devLogin === false ? 'false' : 'true',
  });
  const db = createDb(env.DATABASE_URL);
  const app = await buildApp({
    env,
    db,
    logger: false,
    social: fakeSocial,
    now: opts.now,
    rateLimit: opts.rateLimit ?? false,
  });
  return { app, db };
}

/** 사용자 관련 데이터를 비운다(연쇄 삭제) */
export async function resetUsers(db: Db): Promise<void> {
  await db.user.deleteMany({});
}
