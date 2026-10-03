// 스케줄 저장·조회 (서버 권위). 매일 03:00 KST에 향후 7일치를 다시 만든다(SPEC 4.3).
import { createHash } from 'node:crypto';
import type { Db } from '../db.js';
import { SCHEDULE_SEED } from './catalog-plan.js';
import { buildPlan, type GoatSpec, type SchedulePlan } from './plan.js';
import { generateStops, TIME } from './timeline.js';

export const HORIZON_DAYS = 7;
/** 지난 정류는 이 기간만 남긴다 */
const KEEP_PAST_MS = 3 * TIME.DAY;

export class ScheduleService {
  private cached: { key: string; plan: SchedulePlan } | null = null;

  constructor(
    private readonly db: Db,
    private readonly seed: string = SCHEDULE_SEED,
  ) {}

  /** DB의 활성 염소·지역으로 계획을 만든다. 입력이 같으면 캐시를 쓴다. */
  async plan(): Promise<SchedulePlan> {
    const [goats, regions] = await Promise.all([
      this.db.goat.findMany({
        where: { active: true, kind: { not: 'ROLLING_CITY' } },
        orderBy: { id: 'asc' },
      }),
      this.db.region.findMany({ where: { active: true }, orderBy: { code: 'asc' } }),
    ]);
    const specs: GoatSpec[] = goats.map((g) => ({
      id: g.id,
      kind: g.kind,
      speedKmh: g.speedKmh,
      stayMinMin: g.stayMinMin,
      stayMaxMin: g.stayMaxMin,
      scopeCode: g.scopeCode,
    }));
    const nodes = regions.map((r) => ({
      code: r.code,
      lon: r.lon,
      lat: r.lat,
      provinceCode: r.provinceCode,
    }));
    const key = createHash('sha1')
      .update(JSON.stringify([this.seed, specs, nodes]))
      .digest('hex');
    if (this.cached?.key !== key) this.cached = { key, plan: buildPlan(nodes, specs, this.seed) };
    return this.cached.plan;
  }

  /**
   * [now, now+7일] 정류를 다시 만든다. 앞으로의 일반 정류는 지우고 새로 넣는다
   * (염소 능력치·지역이 바뀌어도 반영되도록). 특급 배달 정류는 남긴다.
   */
  async refresh(now: Date): Promise<{ inserted: number }> {
    const plan = await this.plan();
    const from = now.getTime();
    const to = from + HORIZON_DAYS * TIME.DAY;
    const stops = generateStops(plan, from, to);
    const result = await this.db.$transaction(async (tx) => {
      await tx.goatScheduleStop.deleteMany({
        where: { express: false, arriveAt: { gte: now } },
      });
      await tx.goatScheduleStop.deleteMany({
        where: { departAt: { lt: new Date(from - KEEP_PAST_MS) } },
      });
      return tx.goatScheduleStop.createMany({
        data: stops.map((s) => ({
          goatId: s.goatId,
          regionCode: s.regionCode,
          seq: s.seq,
          arriveAt: new Date(s.arriveAt),
          departAt: new Date(s.departAt),
          travelMode: s.travelMode,
        })),
        skipDuplicates: true,
      });
    });
    return { inserted: result.count };
  }

  /** 창에 걸치는 정류. 저장분이 창 끝까지 없으면 먼저 채운다. */
  async window(from: Date, to: Date) {
    const latest = await this.db.goatScheduleStop.findFirst({
      orderBy: { arriveAt: 'desc' },
      select: { arriveAt: true },
    });
    if (!latest || latest.arriveAt < to) await this.refresh(from);
    return this.db.goatScheduleStop.findMany({
      where: { departAt: { gte: from }, arriveAt: { lte: to } },
      orderBy: [{ arriveAt: 'asc' }, { goatId: 'asc' }],
    });
  }
}
