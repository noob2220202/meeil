// 관리자 계정 만들기/비밀번호·TOTP 재설정(비대화형)
//   ADMIN_PASSWORD=... pnpm --filter @meeil/server admin:create <username> [ADMIN|MODERATOR]
//   (컨테이너: node dist/admin/cli.js <username> [role])
import 'dotenv/config';
import { randomBytes } from 'node:crypto';
import { createDb } from '../db.js';
import { adminSecretKey, loadEnv } from '../env.js';
import { hashPassword, newTotpSecret, otpauthUri, seal } from './crypto.js';

async function main() {
  const [username, roleArg = 'MODERATOR'] = process.argv.slice(2);
  if (!username || !/^[a-z0-9_.-]{3,40}$/.test(username)) {
    console.error('사용법: admin:create <username(영문 소문자·숫자 3~40)> [ADMIN|MODERATOR]');
    process.exit(1);
  }
  const role = roleArg === 'ADMIN' ? 'ADMIN' : 'MODERATOR';
  const env = loadEnv();
  const db = createDb(env.DATABASE_URL);
  const password = process.env.ADMIN_PASSWORD ?? randomBytes(12).toString('base64url');
  if (password.length < 12) throw new Error('ADMIN_PASSWORD는 12자 이상이어야 합니다');
  const secret = newTotpSecret();
  const data = {
    passwordHash: await hashPassword(password),
    totpSecret: seal(secret, adminSecretKey(env)),
    role,
    disabled: false,
  } as const;
  await db.adminUser.upsert({ where: { username }, create: { username, ...data }, update: data });
  console.log(`관리자 ${username} (${role}) 준비 완료`);
  if (!process.env.ADMIN_PASSWORD) console.log(`비밀번호: ${password}`);
  console.log(`인증 앱 등록 URI: ${otpauthUri(username, secret)}`);
  console.log(`(수동 입력 키: ${secret})`);
  await db.$disconnect();
}

void main();
