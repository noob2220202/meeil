import type { Db } from '../db.js';

/** 지금 [regionCode]에 머무는 배달 염소들(서버 스케줄 기준) */
export async function deliveryGoatsStayingAt(db: Db, regionCode: string, at: Date) {
  const stops = await db.goatScheduleStop.findMany({
    where: {
      regionCode,
      arriveAt: { lte: at },
      departAt: { gt: at },
      goat: { kind: 'DELIVERY', active: true },
    },
    include: { goat: { select: { id: true, name: true } } },
    orderBy: { arriveAt: 'asc' },
  });
  return stops.map((s) => s.goat);
}
