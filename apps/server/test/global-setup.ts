// 테스트 전용 DB(meeil_test)를 만들고 마이그레이션을 적용한다. 개발 DB 데이터는 건드리지 않는다.
import 'dotenv/config';
import { execSync } from 'node:child_process';
import pg from 'pg';

export function testDatabaseUrl(): string {
  if (process.env.TEST_DATABASE_URL) return process.env.TEST_DATABASE_URL;
  const url = new URL(process.env.DATABASE_URL ?? 'postgresql://meeil:meeil@localhost:5432/meeil');
  url.pathname = `${url.pathname.replace(/^\//, '')}_test`;
  return url.toString();
}

export default async function setup(): Promise<void> {
  const url = new URL(testDatabaseUrl());
  const dbName = url.pathname.replace(/^\//, '');
  const admin = new URL(url);
  admin.pathname = '/postgres';
  const client = new pg.Client({ connectionString: admin.toString() });
  await client.connect();
  const exists = await client.query('SELECT 1 FROM pg_database WHERE datname = $1', [dbName]);
  if (exists.rowCount === 0) await client.query(`CREATE DATABASE "${dbName.replace(/"/g, '')}"`);
  await client.end();
  execSync('npx prisma migrate deploy', {
    env: { ...process.env, DATABASE_URL: url.toString() },
    stdio: 'pipe',
  });
  process.env.TEST_DATABASE_URL = url.toString();
}
