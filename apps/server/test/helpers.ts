import 'dotenv/config';
import type { FastifyInstance } from 'fastify';
import { buildApp } from '../src/app.js';
import { createDb, type Db } from '../src/db.js';
import { loadEnv } from '../src/env.js';

/** 실제 PostgreSQL(DATABASE_URL)에 붙는 통합 테스트용 앱 */
export async function createTestApp(): Promise<{ app: FastifyInstance; db: Db }> {
  const env = loadEnv({ ...process.env, NODE_ENV: 'test' });
  const db = createDb(env.DATABASE_URL);
  const app = await buildApp({ env, db, logger: false });
  return { app, db };
}
