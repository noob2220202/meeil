import 'dotenv/config';
import type { FastifyInstance } from 'fastify';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { buildApp } from '../src/app.js';
import { MemoryPusher } from '../src/push/push.js';
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
): Promise<{ app: FastifyInstance; db: Db; pusher: MemoryPusher }> {
  const env = loadEnv({
    ...process.env,
    NODE_ENV: 'test',
    DATABASE_URL: testDatabaseUrl(),
    STORAGE_DRIVER: 'local',
    LOCAL_STORAGE_DIR: join(tmpdir(), 'meeil-test-storage'),
    PUBLIC_BASE_URL: 'http://media.test',
    JOBS_ENABLED: 'false',
    JWT_SECRET: process.env.JWT_SECRET ?? 'test-secret-0123456789abcdef0123456789',
    AUTH_DEV_LOGIN: opts.devLogin === false ? 'false' : 'true',
  });
  const db = createDb(env.DATABASE_URL);
  const pusher = new MemoryPusher();
  const app = await buildApp({
    pusher,
    env,
    db,
    logger: false,
    social: fakeSocial,
    now: opts.now,
    rateLimit: opts.rateLimit ?? false,
  });
  return { app, db, pusher };
}

/** 사용자 관련 데이터를 비운다(연쇄 삭제) */
export async function resetUsers(db: Db): Promise<void> {
  // 사용자를 참조하는 편지·신고·차단부터
  await db.report.deleteMany({});
  await db.letter.updateMany({ data: { replyToId: null } });
  await db.letter.deleteMany({});
  await db.letterPhoto.deleteMany({});
  await db.user.deleteMany({});
}
