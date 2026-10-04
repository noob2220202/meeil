import 'dotenv/config';
import cluster from 'node:cluster';
import { buildApp, createPusher, createStorage } from './app.js';
import { createDb } from './db.js';
import { loadEnv } from './env.js';
import { startJobs } from './jobs.js';
import { ScheduleService } from './schedule/service.js';

const env = loadEnv();

/**
 * WEB_CONCURRENCY>1이면 CPU 코어 수만큼 워커 프로세스를 띄운다(부하 테스트 결과, docs/LOADTEST.md).
 * 배경 작업(pg-boss)은 1번 워커만 돌린다. 요청 제한 카운터는 워커마다 따로라 실제 한도는 ×N이 된다.
 */
if (env.WEB_CONCURRENCY > 1 && cluster.isPrimary) {
  const spawn = (index: number) => {
    const worker = cluster.fork({ WORKER_INDEX: String(index) });
    worker.on('exit', (code, signal) => {
      if (stopping) return;
      console.error(`워커 ${index} 종료(code=${code}, signal=${signal}), 다시 띄웁니다`);
      setTimeout(() => spawn(index), 1000);
    });
  };
  let stopping = false;
  for (let i = 1; i <= env.WEB_CONCURRENCY; i++) spawn(i);
  const stop = () => {
    stopping = true;
    for (const w of Object.values(cluster.workers ?? {})) w?.process.kill('SIGTERM');
  };
  process.on('SIGINT', stop);
  process.on('SIGTERM', stop);
} else {
  await serve(process.env.WORKER_INDEX ? process.env.WORKER_INDEX === '1' : true);
}

async function serve(runJobs: boolean) {
  const db = createDb(env.DATABASE_URL, env.DATABASE_POOL_MAX);
  const schedule = new ScheduleService(db);
  const storage = createStorage(env);
  const pusher = createPusher(env, db);
  const app = await buildApp({ env, db, schedule, storage, pusher });
  const boss =
    env.JOBS_ENABLED && runJobs
      ? await startJobs({
          databaseUrl: env.DATABASE_URL,
          db,
          schedule,
          letters: app.letters,
          eat: app.eat,
          account: app.account,
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
}
