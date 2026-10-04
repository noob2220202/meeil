import { PrismaPg } from '@prisma/adapter-pg';
import { PrismaClient } from './generated/prisma/client.js';

export type Db = PrismaClient;

/** [poolMax]: 서버 프로세스 하나가 여는 최대 DB 연결 수(docs/LOADTEST.md) */
export function createDb(databaseUrl: string, poolMax = 10): Db {
  return new PrismaClient({
    adapter: new PrismaPg({ connectionString: databaseUrl, max: poolMax }),
  });
}
