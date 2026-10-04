// 스케줄 시뮬레이터 테스트 (CLAUDE.md: CI 필수, 깨지면 다음 단계로 가지 않는다)
// 30일치를 생성해 "모든 시는 48시간 안에 방문, 도착 하드캡 72시간"을 검증한다.
import { describe, expect, it } from 'vitest';
import { buildCatalogPlan } from './catalog-plan.js';
import { generateStops, SCHEDULE_EPOCH, TIME } from './timeline.js';
import { verifySchedule } from './verify.js';
import {
  DELIVERY_CYCLE_TARGET_MIN,
  NATION_BUDGET_MIN,
  PROVINCE_BUDGET_MIN,
  routeTravelMinutes,
} from './plan.js';

const plan = buildCatalogPlan();

describe('계획(구조적 보장)', () => {
  it('모든 시가 배달 염소 한 마리에게 정확히 한 번 배정된다', () => {
    const assigned = plan.delivery.flatMap((r) => r.tour);
    expect(new Set(assigned).size).toBe(assigned.length);
    expect(new Set(assigned)).toEqual(new Set(plan.regions.keys()));
    expect(plan.delivery).toHaveLength(12);
  });

  it('체류를 모두 최대로 잡아도 배달 염소 한 바퀴는 46시간 이내', () => {
    for (const r of plan.delivery) {
      const g = plan.goats.get(r.goatId)!;
      const worst =
        routeTravelMinutes(plan.regions, r.tour, g.speedKmh) + r.tour.length * r.stayMaxMin;
      expect(worst, r.goatId).toBeLessThanOrEqual(DELIVERY_CYCLE_TARGET_MIN);
      // 체류가 너무 짧아지면 편지를 맡길 틈이 없다
      expect(r.stayMinMin, r.goatId).toBeGreaterThanOrEqual(30);
    }
  });

  it('롤링 염소는 주기 안에 순회를 마친다', () => {
    const fits = (r: (typeof plan.provinces)[number], budget: number) => {
      const g = plan.goats.get(r.goatId)!;
      return (
        routeTravelMinutes(plan.regions, r.tour, g.speedKmh) + r.tour.length * r.stayMaxMin <=
        budget
      );
    };
    expect(fits(plan.nation!, NATION_BUDGET_MIN)).toBe(true);
    expect(plan.nation!.tour).toHaveLength(plan.regions.size);
    for (const r of plan.provinces) expect(fits(r, PROVINCE_BUDGET_MIN), r.goatId).toBe(true);
  });

  it('같은 입력이면 같은 계획(결정적)', () => {
    const again = buildCatalogPlan();
    expect(again.delivery).toEqual(plan.delivery);
  });
});

describe.each([
  ['기준 직후', SCHEDULE_EPOCH],
  ['2026-10 출시 무렵', Date.UTC(2026, 9, 1)],
  ['1년 뒤', Date.UTC(2027, 9, 1)],
])('30일 시뮬레이션: %s', (_label, start) => {
  const from = start;
  const to = from + 30 * TIME.DAY;
  const stops = generateStops(plan, from, to);
  const report = verifySchedule(plan, stops, from, to, { letters: 5000 });

  it('제약 위반이 없다', () => {
    expect(report.errors).toEqual([]);
  });
  it('모든 시는 48시간 안에 배달 염소가 온다', () => {
    expect(report.maxEmptyGapMin).toBeLessThanOrEqual(48 * 60);
  });
  it('편지는 72시간 안에 도착하고 특급 배달이 필요 없다', () => {
    expect(report.etaMaxMin).toBeLessThanOrEqual(72 * 60);
    expect(report.expressCount).toBe(0);
  });
});

describe('재생성 일관성', () => {
  it('창을 다르게 잘라도 겹치는 정류는 같다', () => {
    const a = generateStops(plan, Date.UTC(2026, 9, 1), Date.UTC(2026, 9, 5));
    const b = generateStops(plan, Date.UTC(2026, 9, 3), Date.UTC(2026, 9, 8));
    const key = (s: (typeof a)[number]) => `${s.goatId}:${s.seq}`;
    const bMap = new Map(b.map((s) => [key(s), s]));
    const shared = a.filter((s) => bMap.has(key(s)));
    expect(shared.length).toBeGreaterThan(50);
    for (const s of shared) expect(bMap.get(key(s))).toEqual(s);
  });
});
