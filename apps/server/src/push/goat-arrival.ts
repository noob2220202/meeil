// "우체부 염소가 우리 동네에 왔어요" 알림. 염소가 머무는 시간이 짧으므로(평균 하루 1시간 남짓)
// 편지를 맡길 기회를 놓치지 않게 알려 준다(docs/DECISIONS.md M2 리스크 대응).
import type { Db } from '../db.js';
import type { Pusher } from './push.js';

/** 한 사람에게 이 간격보다 자주 보내지 않는다 */
export const GOAT_NOTIFY_MIN_GAP_MS = 6 * 60 * 60 * 1000;
/** 최근에 앱을 쓴 사람에게만 */
const ACTIVE_WITHIN_MS = 14 * 24 * 60 * 60 * 1000;

/** (now - windowMs, now] 사이에 도착한 배달 염소마다 그 시 사람들에게 알린다. 보낸 사람 수를 돌려준다. */
export async function notifyGoatArrivals(
  db: Db,
  pusher: Pusher,
  now: Date,
  windowMs: number,
): Promise<number> {
  const stops = await db.goatScheduleStop.findMany({
    where: {
      arriveAt: { gt: new Date(now.getTime() - windowMs), lte: now },
      departAt: { gt: now },
      goat: { kind: 'DELIVERY', active: true },
    },
    include: { goat: { select: { name: true } }, region: { select: { name: true } } },
  });
  let notified = 0;
  for (const stop of stops) {
    const users = await db.user.findMany({
      where: {
        lastRegionCode: stop.regionCode,
        notifyEnabled: true,
        status: 'ACTIVE',
        lastActiveAt: { gte: new Date(now.getTime() - ACTIVE_WITHIN_MS) },
        OR: [
          { lastGoatNotifiedAt: null },
          { lastGoatNotifiedAt: { lt: new Date(now.getTime() - GOAT_NOTIFY_MIN_GAP_MS) } },
        ],
        fcmTokens: { some: {} },
      },
      select: { id: true },
      take: 5000,
    });
    const minutes = Math.max(1, Math.round((stop.departAt.getTime() - now.getTime()) / 60_000));
    for (const u of users) {
      // 먼저 표시해 두어 중복 발송을 막는다
      const { count } = await db.user.updateMany({
        where: {
          id: u.id,
          OR: [
            { lastGoatNotifiedAt: null },
            { lastGoatNotifiedAt: { lt: new Date(now.getTime() - GOAT_NOTIFY_MIN_GAP_MS) } },
          ],
        },
        data: { lastGoatNotifiedAt: now },
      });
      if (count === 0) continue;
      await pusher
        .sendToUser(u.id, {
          title: '우체부 염소가 왔어요!',
          body: `${stop.goat.name}가 ${stop.region.name}에 도착했어요. 약 ${minutes}분 머무는 동안 편지를 맡겨 보세요.`,
          data: { type: 'goat', goatId: stop.goatId, regionCode: stop.regionCode },
        })
        .catch(() => 0);
      notified++;
    }
  }
  return notified;
}

/** 편지에 붙지 않은 채 하루가 지난 사진 정리 */
export const ORPHAN_PHOTO_MS = 24 * 60 * 60 * 1000;
