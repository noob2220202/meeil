import type { FastifyPluginAsync } from 'fastify';
import { z } from 'zod';
import { ROLLING_COLORS } from '../catalog/goats.js';
import { parse } from '../errors.js';
import { TtlCache } from '../lib/ttl-cache.js';
import type { ScheduleService } from '../schedule/service.js';

const Query = z.object({
  /** 앞으로 몇 시간치를 받을지 */
  hours: z.coerce.number().int().min(1).max(72).default(36),
});

/** 현재 위치를 보간하려면 지금 직전 정류도 필요하다 */
const LOOKBACK_MS = 6 * 60 * 60 * 1000;

/**
 * 염소 스케줄 (SPEC 4.3). 클라이언트는 이 정류 목록을 보간해 위치를 그리고,
 * serverTime으로 기기 시계 오차를 보정한다. 시 롤링 염소는 자기 시에 상주하므로 정류가 없다.
 */
export const goatRoutes: FastifyPluginAsync<{
  schedule: ScheduleService;
  now: () => Date;
  /**
   * 같은 시간 칸(이 길이) 안의 요청은 같은 응답 본문을 나눠 쓴다. 모두에게 같은 공개 정보라
   * 앱 전체에서 가장 자주 불리는 무거운 조회를 DB에서 덜어 준다(docs/LOADTEST.md). 0이면 끈다.
   */
  cacheMs: number;
}> = async (app, { schedule, now, cacheMs }) => {
  const cache = new TtlCache<Awaited<ReturnType<typeof load>>>(cacheMs);

  async function load(hours: number, t: Date) {
    const from = new Date(t.getTime() - LOOKBACK_MS);
    const to = new Date(t.getTime() + hours * 60 * 60 * 1000);
    const [goats, stops, region] = await Promise.all([
      app.db.goat.findMany({
        where: { active: true, kind: { not: 'ROLLING_CITY' } },
        orderBy: { sortOrder: 'asc' },
        select: {
          id: true,
          kind: true,
          name: true,
          scopeCode: true,
          speedKmh: true,
          hatColor: true,
          bagColor: true,
        },
      }),
      schedule.window(from, to),
      app.db.region.findFirst({ where: { active: true }, select: { version: true } }),
    ]);
    return {
      regionVersion: region?.version ?? null,
      from: from.toISOString(),
      to: to.toISOString(),
      goats,
      cityGoat: { hatColor: ROLLING_COLORS.CITY.hat, bagColor: ROLLING_COLORS.CITY.bag },
      stops: stops.map((s) => ({
        goatId: s.goatId,
        regionCode: s.regionCode,
        arriveAt: s.arriveAt.toISOString(),
        departAt: s.departAt.toISOString(),
        travelMode: s.travelMode,
        express: s.express,
      })),
    };
  }

  app.get('/goats/schedule', async (req) => {
    const { hours } = parse(Query, req.query);
    const t = now();
    const body =
      cacheMs > 0
        ? await cache.get(`${hours}:${Math.floor(t.getTime() / cacheMs)}`, () => load(hours, t))
        : await load(hours, t);
    // 기기 시계 보정용 서버 시각은 캐시와 상관없이 지금 값
    return { serverTime: t.toISOString(), ...body };
  });
};
