// 편지 도착 시각 (SPEC 4.3): 맡긴 뒤 목적지 시에 배달 염소가 다음으로 도착하는 시각.
// 72시간 안에 방문이 없으면 가장 빠른 염소가 "특급 배달"로 강제 도착한다.
import type { Stop } from './timeline.js';
import { TIME } from './timeline.js';

/** 맡기자마자 도착하지 않도록 최소 이동 시간 [제안] */
export const MIN_TRANSIT_MS = 1 * TIME.HOUR;
export const HARD_CAP_MS = 72 * TIME.HOUR;

export interface Eta {
  arriveAt: number;
  goatId: string;
  express: boolean;
}

/** 지역별 배달 염소 도착 시각 색인(오름차순) */
export function indexArrivals(stops: readonly Stop[], deliveryGoats: ReadonlySet<string>) {
  const byRegion = new Map<string, Stop[]>();
  for (const s of stops) {
    if (!deliveryGoats.has(s.goatId)) continue;
    let list = byRegion.get(s.regionCode);
    if (!list) byRegion.set(s.regionCode, (list = []));
    list.push(s);
  }
  for (const list of byRegion.values()) list.sort((a, b) => a.arriveAt - b.arriveAt);
  return byRegion;
}

export function computeEta(
  arrivals: ReadonlyMap<string, readonly Stop[]>,
  destRegion: string,
  handedAt: number,
  expressGoatId: string,
): Eta {
  const earliest = handedAt + MIN_TRANSIT_MS;
  const list = arrivals.get(destRegion) ?? [];
  // 이진 탐색으로 earliest 이후 첫 도착
  let lo = 0;
  let hi = list.length;
  while (lo < hi) {
    const mid = (lo + hi) >> 1;
    if (list[mid]!.arriveAt < earliest) lo = mid + 1;
    else hi = mid;
  }
  const next = list[lo];
  if (next && next.arriveAt <= handedAt + HARD_CAP_MS) {
    return { arriveAt: next.arriveAt, goatId: next.goatId, express: false };
  }
  return { arriveAt: handedAt + HARD_CAP_MS, goatId: expressGoatId, express: true };
}
