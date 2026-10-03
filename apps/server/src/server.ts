import 'dotenv/config';
import { buildApp, createPusher, createStorage } from './app.js';
import { createDb } from './db.js';
import { loadEnv } from './env.js';
import { startJobs } from './jobs.js';
import { ScheduleService } from './schedule/service.js';

const env = loadEnv();
const db = createDb(env.DATABASE_URL);
const schedule = new ScheduleService(db);
const storage = createStorage(env);
const pusher = createPusher(env, db);
const app = await buildApp({ env, db, schedule, storage, pusher });
const boss = env.JOBS_ENABLED
  ? await startJobs({
      databaseUrl: env.DATABASE_URL,
      db,
      schedule,
      letters: app.letters,
      eat: app.eat,
      pusher,
      storage,
      log: app.log,
    })
  : null;

const shutdown = async (signal: string) => {
  app.log.info(`${signal} 수신, 종료합니다`);
  await boss?.stop();
  await app.close();
  await db.$disconnect();
  process.exit(0);
};
process.on('SIGINT', () => void shutdown('SIGINT'));
process.on('SIGTERM', () => void shutdown('SIGTERM'));

await app.listen({ port: env.PORT, host: env.HOST });
