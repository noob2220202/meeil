// 배치 작업 (pg-boss, Redis 없이 PostgreSQL만)
import type { FastifyBaseLogger } from 'fastify';
import { PgBoss } from 'pg-boss';
import type { Db } from './db.js';
import type { LetterService } from './letters/service.js';
import { notifyGoatArrivals, ORPHAN_PHOTO_MS } from './push/goat-arrival.js';
import type { Pusher } from './push/push.js';
import type { ScheduleService } from './schedule/service.js';
import type { Storage } from './storage/storage.js';

const SCHEDULE_REFRESH = 'schedule-refresh';
const DELIVER_LETTERS = 'deliver-letters';
const GOAT_ARRIVAL_NOTIFY = 'goat-arrival-notify';
const DAILY_CLEANUP = 'daily-cleanup';
const GOAT_NOTIFY_EVERY_MS = 5 * 60 * 1000;
const REPORT_PRUNE_DAYS = 7;

export async function startJobs(opts: {
  databaseUrl: string;
  db: Db;
  schedule: ScheduleService;
  letters: LetterService;
  pusher: Pusher;
  storage: Storage;
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

  // 매분: 도착 시각이 지난 편지 배달 + 푸시
  await boss.createQueue(DELIVER_LETTERS);
  await boss.schedule(DELIVER_LETTERS, '* * * * *', null, { tz: 'Asia/Seoul' });
  await boss.work(DELIVER_LETTERS, async () => {
    const n = await opts.letters.deliverDue();
    if (n > 0) opts.log.info({ delivered: n }, '편지 배달');
  });

  // 5분마다: 우리 동네에 염소가 오면 알림
  await boss.createQueue(GOAT_ARRIVAL_NOTIFY);
  await boss.schedule(GOAT_ARRIVAL_NOTIFY, '*/5 * * * *', null, { tz: 'Asia/Seoul' });
  await boss.work(GOAT_ARRIVAL_NOTIFY, async () => {
    const n = await notifyGoatArrivals(opts.db, opts.pusher, new Date(), GOAT_NOTIFY_EVERY_MS);
    if (n > 0) opts.log.info({ notified: n }, '염소 도착 알림');
  });

  // 매일 04:00 KST: 휴지통 30일 경과분·주인 없는 사진 정리
  await boss.createQueue(DAILY_CLEANUP);
  await boss.schedule(DAILY_CLEANUP, '0 4 * * *', null, { tz: 'Asia/Seoul' });
  await boss.work(DAILY_CLEANUP, async () => {
    const purged = await opts.letters.purgeExpiredTrash();
    const orphans = await opts.db.letterPhoto.findMany({
      where: { letterId: null, createdAt: { lt: new Date(Date.now() - ORPHAN_PHOTO_MS) } },
      select: { id: true, storageKey: true },
    });
    for (const p of orphans) {
      await opts.storage.delete(p.storageKey).catch(() => undefined);
      await opts.db.letterPhoto.delete({ where: { id: p.id } });
    }
    opts.log.info({ purged, orphanPhotos: orphans.length }, '매일 정리');
  });

  // 기동 직후에도 한 번 채운다(배포 사이에 03시를 놓쳤을 수 있음)
  const { inserted } = await opts.schedule.refresh(new Date());
  opts.log.info({ inserted }, '기동 시 스케줄 갱신');
  return boss;
}
