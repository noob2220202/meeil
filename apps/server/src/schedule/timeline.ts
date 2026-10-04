// 계획 → 실제 정류(도착·출발 시각) 생성. 같은 계획이면 어느 창(window)을 뽑아도 결과가 같다.
import { isSeaLeg } from './geo.js';
import { legMinutes, type GoatRoute, type SchedulePlan } from './plan.js';
import { randInt } from './rng.js';

const MIN = 60_000;
const HOUR = 60 * MIN;
const DAY = 24 * HOUR;

/** 스케줄 기준 시각: 2026-01-05(월) 00:00 KST. 주·3일 주기도 여기서 센다. */
export const SCHEDULE_EPOCH = Date.UTC(2026, 0, 4, 15, 0, 0);
export const NATION_PERIOD_MS = 7 * DAY;
export const PROVINCE_PERIOD_MS = 3 * DAY;

export type TravelMode = 'WALK' | 'SEA';

export interface Stop {
  goatId: string;
  regionCode: string;
  /** 염소별 고유 순번(재생성해도 같은 값) */
  seq: number;
  arriveAt: number;
  departAt: number;
  /** 이 정류에 오기까지의 이동 수단 */
  travelMode: TravelMode;
}

function stayMinutes(plan: SchedulePlan, route: GoatRoute, key: string): number {
  return randInt(`${plan.seed}:${route.goatId}:${key}`, route.stayMinMin, route.stayMaxMin);
}

// ───────── 배달 염소: 기준 시각부터 쉬지 않고 순회를 반복 ─────────

/** 염소별 바퀴 시작 시각 캐시 */
const cycleStartCache = new WeakMap<SchedulePlan, Map<string, number[]>>();

function cycleStarts(plan: SchedulePlan, route: GoatRoute): number[] {
  let byGoat = cycleStartCache.get(plan);
  if (!byGoat) cycleStartCache.set(plan, (byGoat = new Map()));
  let starts = byGoat.get(route.goatId);
  if (!starts) byGoat.set(route.goatId, (starts = [SCHEDULE_EPOCH]));
  return starts;
}

function cycleDuration(plan: SchedulePlan, route: GoatRoute, cycle: number): number {
  const speed = plan.goats.get(route.goatId)!.speedKmh;
  const n = route.tour.length;
  let ms = 0;
  for (let i = 0; i < n; i++) {
    ms += stayMinutes(plan, route, `${cycle}:${i}`) * MIN;
    ms += legMinutes(plan.regions, route.tour[i]!, route.tour[(i + 1) % n]!, speed) * MIN;
  }
  return ms;
}

function deliveryStops(plan: SchedulePlan, route: GoatRoute, from: number, to: number): Stop[] {
  const starts = cycleStarts(plan, route);
  // from을 포함하는 바퀴까지 시작 시각을 늘려 둔다
  while (starts[starts.length - 1]! <= from) {
    const c = starts.length - 1;
    starts.push(starts[c]! + cycleDuration(plan, route, c));
  }
  let cycle = Math.max(0, starts.findIndex((s) => s > from) - 1);
  const speed = plan.goats.get(route.goatId)!.speedKmh;
  const n = route.tour.length;
  const out: Stop[] = [];
  for (;;) {
    if (cycle + 1 >= starts.length) starts.push(starts[cycle]! + cycleDuration(plan, route, cycle));
    let t = starts[cycle]!;
    if (t > to) break;
    for (let i = 0; i < n; i++) {
      const code = route.tour[i]!;
      const prev = route.tour[(i - 1 + n) % n]!;
      const arriveAt = t;
      const departAt = arriveAt + stayMinutes(plan, route, `${cycle}:${i}`) * MIN;
      if (departAt >= from && arriveAt <= to) {
        out.push({
          goatId: route.goatId,
          regionCode: code,
          seq: cycle * n + i,
          arriveAt,
          departAt,
          travelMode: isSeaLeg(prev, code) ? 'SEA' : 'WALK',
        });
      }
      t = departAt + legMinutes(plan.regions, code, route.tour[(i + 1) % n]!, speed) * MIN;
    }
    cycle++;
  }
  return out;
}

// ───────── 롤링 염소(전국·도): 주기마다 처음부터 순회, 남는 시간은 출발지에서 쉰다 ─────────

function periodStops(
  plan: SchedulePlan,
  route: GoatRoute,
  period: number,
  periodMs: number,
): Stop[] {
  const speed = plan.goats.get(route.goatId)!.speedKmh;
  const n = route.tour.length;
  const start = SCHEDULE_EPOCH + period * periodMs;
  const end = start + periodMs;
  const out: Stop[] = [];
  let t = start;
  for (let i = 0; i < n; i++) {
    const code = route.tour[i]!;
    const prev = i === 0 ? route.tour[n - 1]! : route.tour[i - 1]!;
    const departAt = t + stayMinutes(plan, route, `p${period}:${i}`) * MIN;
    out.push({
      goatId: route.goatId,
      regionCode: code,
      seq: period * 10_000 + i,
      arriveAt: t,
      departAt,
      travelMode: isSeaLeg(prev, code) ? 'SEA' : 'WALK',
    });
    t =
      departAt + (i < n - 1 ? legMinutes(plan.regions, code, route.tour[i + 1]!, speed) * MIN : 0);
  }
  // 마지막 지역에서 출발지로 돌아가 다음 주기 시작까지 쉰다
  if (n > 1) {
    const last = route.tour[n - 1]!;
    const back = t + legMinutes(plan.regions, last, route.tour[0]!, speed) * MIN;
    out.push({
      goatId: route.goatId,
      regionCode: route.tour[0]!,
      seq: period * 10_000 + n,
      arriveAt: Math.min(back, end),
      departAt: end,
      travelMode: isSeaLeg(last, route.tour[0]!) ? 'SEA' : 'WALK',
    });
  } else {
    out[out.length - 1]!.departAt = end;
  }
  return out;
}

function periodicStops(
  plan: SchedulePlan,
  route: GoatRoute,
  periodMs: number,
  from: number,
  to: number,
): Stop[] {
  // 경계 정류를 합칠 때 창 위치와 무관하게 같은 결과가 나오도록 앞뒤 주기를 하나씩 더 만든다
  const first = Math.max(0, Math.floor((from - SCHEDULE_EPOCH) / periodMs) - 1);
  const last = Math.max(0, Math.floor((to - SCHEDULE_EPOCH) / periodMs)) + 1;
  const all: Stop[] = [];
  for (let p = first; p <= last; p++) all.push(...periodStops(plan, route, p, periodMs));
  // 한 주기의 "복귀 정류"와 다음 주기의 첫 정류는 같은 곳에 이어서 머무는 것이므로 하나로 합친다.
  // 지역이 하나뿐인 도(세종)는 합치면 끝없이 이어지므로 합치지 않는다.
  const n = route.tour.length;
  const merged: Stop[] = [];
  for (const s of all) {
    const prev = merged[merged.length - 1];
    const isReturn = prev !== undefined && n > 1 && prev.seq % 10_000 === n && s.seq % 10_000 === 0;
    if (isReturn && prev.regionCode === s.regionCode && prev.departAt >= s.arriveAt) {
      prev.departAt = s.departAt;
    } else {
      merged.push({ ...s });
    }
  }
  return merged.filter((s) => s.departAt >= from && s.arriveAt <= to);
}

/** 창 [from, to] 안에 걸치는 모든 정류(배달·전국·도 롤링). 시 롤링 염소는 상주하므로 정류가 없다. */
export function generateStops(plan: SchedulePlan, from: number, to: number): Stop[] {
  const out: Stop[] = [];
  for (const r of plan.delivery) out.push(...deliveryStops(plan, r, from, to));
  if (plan.nation) out.push(...periodicStops(plan, plan.nation, NATION_PERIOD_MS, from, to));
  for (const r of plan.provinces) out.push(...periodicStops(plan, r, PROVINCE_PERIOD_MS, from, to));
  return out.sort((a, b) => a.arriveAt - b.arriveAt || a.goatId.localeCompare(b.goatId));
}

export const TIME = { MIN, HOUR, DAY };
