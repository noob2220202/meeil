// 스케줄 제약 검증 (시뮬레이터 테스트·CLI 공용)
import { computeEta, indexArrivals } from './eta.js';
import { legMinutes, type SchedulePlan } from './plan.js';
import { rand01 } from './rng.js';
import {
  NATION_PERIOD_MS,
  PROVINCE_PERIOD_MS,
  SCHEDULE_EPOCH,
  TIME,
  type Stop,
} from './timeline.js';

export interface VerifyReport {
  /** 지역별 "비어 있는" 최장 구간(분): 염소가 떠난 뒤 다음 염소가 올 때까지 */
  maxEmptyGapMin: number;
  worstGapRegion: string;
  /** 무작위로 맡긴 편지들의 도착까지 걸린 시간(분) */
  etaP50Min: number;
  etaP95Min: number;
  etaMaxMin: number;
  expressCount: number;
  lettersSimulated: number;
  /** 지역별로 배달 염소가 머무는 시간 비율 평균 */
  avgPresenceRatio: number;
  errors: string[];
}

const percentile = (sorted: number[], p: number) =>
  sorted[Math.min(sorted.length - 1, Math.floor(p * sorted.length))] ?? 0;

export function verifySchedule(
  plan: SchedulePlan,
  stops: readonly Stop[],
  from: number,
  to: number,
  opts: { letters?: number; gapLimitMin?: number } = {},
): VerifyReport {
  const errors: string[] = [];
  const gapLimit = opts.gapLimitMin ?? 48 * 60;
  const deliveryIds = new Set(plan.delivery.map((r) => r.goatId));

  // 1) 염소별 연속성: 정류가 겹치지 않고, 이동 시간만큼 떨어져 있다(순간이동 없음)
  const byGoat = new Map<string, Stop[]>();
  for (const s of stops) {
    let l = byGoat.get(s.goatId);
    if (!l) byGoat.set(s.goatId, (l = []));
    l.push(s);
  }
  for (const [goatId, list] of byGoat) {
    list.sort((a, b) => a.arriveAt - b.arriveAt);
    const speed = plan.goats.get(goatId)!.speedKmh;
    for (let i = 1; i < list.length; i++) {
      const a = list[i - 1]!;
      const b = list[i]!;
      if (b.arriveAt < a.departAt)
        errors.push(`${goatId}: 정류 겹침 ${a.regionCode}→${b.regionCode}`);
      const need = legMinutes(plan.regions, a.regionCode, b.regionCode, speed) * TIME.MIN;
      if (b.arriveAt - a.departAt < need - TIME.MIN) {
        errors.push(`${goatId}: 이동 시간 부족 ${a.regionCode}→${b.regionCode}`);
      }
    }
  }

  // 2) 모든 시는 임의의 48시간 구간에 배달 염소가 최소 1회 방문
  const arrivals = indexArrivals(stops, deliveryIds);
  let maxGap = 0;
  let worstGapRegion = '';
  let presence = 0;
  for (const code of plan.regions.keys()) {
    const list = [...(arrivals.get(code) ?? [])].sort((a, b) => a.arriveAt - b.arriveAt);
    if (list.length === 0) {
      errors.push(`${code}: 배달 염소 방문 없음`);
      continue;
    }
    let lastLeave = from;
    let present = 0;
    for (const s of list) {
      const gap = s.arriveAt - lastLeave;
      if (gap > maxGap) {
        maxGap = gap;
        worstGapRegion = code;
      }
      lastLeave = Math.max(lastLeave, s.departAt);
      present += Math.min(s.departAt, to) - Math.max(s.arriveAt, from);
    }
    const tail = to - lastLeave;
    if (tail > maxGap) {
      maxGap = tail;
      worstGapRegion = code;
    }
    presence += present / (to - from);
  }
  if (maxGap > gapLimit * TIME.MIN) {
    errors.push(
      `${worstGapRegion}: ${Math.round(maxGap / TIME.HOUR)}시간 동안 방문 없음 (한도 48시간)`,
    );
  }

  // 3) 롤링 염소 주기 규칙: 전국은 한 주 안에 전 지역, 도는 3일 안에 도 전체
  const checkPeriod = (goatId: string, codes: string[], periodMs: number, label: string) => {
    const list = byGoat.get(goatId) ?? [];
    const firstP = Math.ceil((from - SCHEDULE_EPOCH) / periodMs);
    const lastP = Math.floor((to - SCHEDULE_EPOCH) / periodMs) - 1;
    for (let p = firstP; p <= lastP; p++) {
      const ps = SCHEDULE_EPOCH + p * periodMs;
      const pe = ps + periodMs;
      const visited = new Set(
        list.filter((s) => s.arriveAt < pe && s.departAt > ps).map((s) => s.regionCode),
      );
      const missing = codes.filter((c) => !visited.has(c));
      if (missing.length > 0)
        errors.push(`${label} ${goatId} ${p}주기: 미방문 ${missing.join(',')}`);
    }
  };
  if (plan.nation) {
    checkPeriod(plan.nation.goatId, [...plan.regions.keys()], NATION_PERIOD_MS, '전국');
  }
  for (const r of plan.provinces) checkPeriod(r.goatId, r.tour, PROVINCE_PERIOD_MS, '도');

  // 4) 편지 도착: 무작위 시각·목적지로 맡겼을 때 72시간 하드캡
  const fastest = [...deliveryIds].sort(
    (a, b) => plan.goats.get(b)!.speedKmh - plan.goats.get(a)!.speedKmh,
  )[0]!;
  const codes = [...plan.regions.keys()];
  const letters = opts.letters ?? 5000;
  // 도착 판정을 위해 마지막 3일은 맡기는 시각에서 뺀다
  const handSpan = to - from - 3 * TIME.DAY;
  const etas: number[] = [];
  let express = 0;
  for (let i = 0; i < letters; i++) {
    const handedAt = from + Math.floor(rand01(`letter:${i}:t`) * handSpan);
    const dest = codes[Math.floor(rand01(`letter:${i}:d`) * codes.length)]!;
    const eta = computeEta(arrivals, dest, handedAt, fastest);
    if (eta.express) express++;
    if (eta.arriveAt - handedAt > 72 * TIME.HOUR) errors.push(`편지 ${i}: 72시간 초과`);
    etas.push((eta.arriveAt - handedAt) / TIME.MIN);
  }
  etas.sort((a, b) => a - b);

  return {
    maxEmptyGapMin: Math.round(maxGap / TIME.MIN),
    worstGapRegion,
    etaP50Min: Math.round(percentile(etas, 0.5)),
    etaP95Min: Math.round(percentile(etas, 0.95)),
    etaMaxMin: Math.round(etas[etas.length - 1] ?? 0),
    expressCount: express,
    lettersSimulated: letters,
    avgPresenceRatio: presence / plan.regions.size,
    errors,
  };
}
