// 배치 작업 (pg-boss, Redis 없이 PostgreSQL만)
import type { FastifyBaseLogger } from 'fastify';
import { PgBoss } from 'pg-boss';
import type { Db } from './db.js';
import type { ScheduleService } from './schedule/service.js';

const SCHEDULE_REFRESH = 'schedule-refresh';
const REPORT_PRUNE_DAYS = 7;

export async function startJobs(opts: {
  databaseUrl: string;
  db: Db;
  schedule: ScheduleService;
  log: FastifyBaseLogger;
}): Promise<PgBoss> {
  const boss = new PgBoss(opts.databaseUrl);
  boss.on('error', (err: unknown) => opts.log.error({ err }, 'pg-boss 오류'));
  await boss.start();

  await boss.createQueue(SCHEDULE_REFRESH);
  // 매일 03:00 KST: 향후 7일치 스케줄 유지 + 오래된 위치 보고 정리
  await boss.schedule(SCHEDULE_REFRESH, '0 3 * * *', null, { tz: 'Asia/Seoul' });
  await boss.work(SCHEDULE_REFRESH, async () => {
    const { inserted } = await opts.schedule.refresh(new Date());
    const cutoff = new Date(Date.now() - REPORT_PRUNE_DAYS * 24 * 60 * 60 * 1000);
    const pruned = await opts.db.userRegionReport.deleteMany({
      where: { reportedAt: { lt: cutoff } },
    });
    opts.log.info({ inserted, prunedReports: pruned.count }, '스케줄 갱신 완료');
  });

  // 기동 직후에도 한 번 채운다(배포 사이에 03시를 놓쳤을 수 있음)
  const { inserted } = await opts.schedule.refresh(new Date());
  opts.log.info({ inserted }, '기동 시 스케줄 갱신');
  return boss;
}
