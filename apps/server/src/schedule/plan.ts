// 염소 담당 구역·순회 경로 계획 (SPEC 4.3). 입력이 같으면 결과도 항상 같다.
import { haversineKm, isSeaLeg } from './geo.js';
import { hash32 } from './rng.js';
import { solveTour, tourLength } from './tour.js';

export interface RegionNode {
  code: string;
  lon: number;
  lat: number;
  provinceCode: string;
}

export type GoatKindName = 'DELIVERY' | 'ROLLING_NATION' | 'ROLLING_PROVINCE' | 'ROLLING_CITY';

export interface GoatSpec {
  id: string;
  kind: GoatKindName;
  speedKmh: number;
  stayMinMin: number;
  stayMaxMin: number;
  scopeCode?: string | null;
}

/** 걷는 길은 직선거리보다 길다 */
export const ROAD_FACTOR = 1.25;
/** 배·비행기 속도(섬 그룹 사이 이동) */
export const SEA_SPEED_KMH = 120;
/** 한 구간 최소 이동 시간 */
export const MIN_LEG_MINUTES = 10;
/** 배달 염소 한 바퀴 최악 시간 목표(48시간 방문 보장에 여유를 둔다) */
export const DELIVERY_CYCLE_TARGET_MIN = 46 * 60;
/** 롤링 염소 한 주기 안에 순회+복귀를 마칠 시간(주기보다 2시간 여유) */
export const NATION_BUDGET_MIN = (7 * 24 - 2) * 60;
export const PROVINCE_BUDGET_MIN = (3 * 24 - 2) * 60;

export interface GoatRoute {
  goatId: string;
  /** 닫힌 순회(마지막 다음은 처음) */
  tour: string[];
  /**
   * 실제로 쓰는 체류 범위(분). 카탈로그 값을 기본으로 하되, 한 바퀴(또는 한 주기)가
   * 목표 시간 안에 반드시 끝나도록 줄인다 → 48시간 방문 보장이 운이 아니라 구조로 성립.
   */
  stayMinMin: number;
  stayMaxMin: number;
}

/** 순회가 [budgetMin] 안에 끝나도록 체류 범위를 줄인다 */
export function fitStays(
  regions: Map<string, RegionNode>,
  tour: readonly string[],
  goat: GoatSpec,
  budgetMin: number,
): { stayMinMin: number; stayMaxMin: number } {
  const travel = routeTravelMinutes(regions, tour, goat.speedKmh);
  const room = Math.floor((budgetMin - travel) / Math.max(1, tour.length));
  if (room < 5) {
    throw new Error(`${goat.id}: 이동만으로 ${Math.round(travel / 60)}시간 — 목표 안에 순회 불가`);
  }
  const stayMaxMin = Math.min(goat.stayMaxMin, room);
  const stayMinMin = Math.min(goat.stayMinMin, Math.max(5, Math.floor(stayMaxMin * 0.6)));
  return { stayMinMin, stayMaxMin };
}

export interface SchedulePlan {
  seed: string;
  regions: Map<string, RegionNode>;
  goats: Map<string, GoatSpec>;
  delivery: GoatRoute[];
  nation: GoatRoute | null;
  provinces: GoatRoute[];
}

export function legMinutes(
  regions: Map<string, RegionNode>,
  from: string,
  to: string,
  speedKmh: number,
): number {
  if (from === to) return 0;
  const a = regions.get(from)!;
  const b = regions.get(to)!;
  const km = haversineKm([a.lon, a.lat], [b.lon, b.lat]);
  const minutes = isSeaLeg(from, to)
    ? (km / SEA_SPEED_KMH) * 60
    : ((km * ROAD_FACTOR) / speedKmh) * 60;
  return Math.max(MIN_LEG_MINUTES, Math.round(minutes));
}

/** 이동 시간 합(분) */
export function routeTravelMinutes(
  regions: Map<string, RegionNode>,
  tour: readonly string[],
  speedKmh: number,
): number {
  if (tour.length < 2) return 0;
  let sum = 0;
  for (let i = 0; i < tour.length; i++) {
    sum += legMinutes(regions, tour[i]!, tour[(i + 1) % tour.length]!, speedKmh);
  }
  return sum;
}

/** 체류를 모두 최대로 잡았을 때 한 바퀴 시간(분) */
export function worstCycleMinutes(
  regions: Map<string, RegionNode>,
  tour: readonly string[],
  goat: GoatSpec,
): number {
  return routeTravelMinutes(regions, tour, goat.speedKmh) + tour.length * goat.stayMaxMin;
}

function solveCodes(regions: Map<string, RegionNode>, codes: readonly string[]): string[] {
  const sorted = [...codes].sort();
  const pts = sorted.map((c) => regions.get(c)!);
  // 경로 모양은 직선거리로 정한다(섬 왕복은 자연히 한 번으로 묶인다)
  const dist = (i: number, j: number) => {
    const d = haversineKm([pts[i]!.lon, pts[i]!.lat], [pts[j]!.lon, pts[j]!.lat]);
    return isSeaLeg(sorted[i]!, sorted[j]!) ? d * 0.6 : d;
  };
  return solveTour(
    sorted.map((_, i) => i),
    dist,
  ).map((i) => sorted[i]!);
}

/**
 * 배달 염소 구역 나누기.
 * 1) 전국 순회 경로를 만들고 2) 염소 수만큼 연속 구간으로 자른 뒤
 * 3) 가장 오래 걸리는 염소의 끝 지역을 옆 염소에게 넘기는 식으로 균형을 맞춘다.
 * 염소 배치 순서를 여러 가지 시도해 최악 한 바퀴 시간이 가장 짧은 안을 고른다.
 */
export function planDelivery(
  regions: Map<string, RegionNode>,
  goats: readonly GoatSpec[],
  seed: string,
  attempts = 16,
): GoatRoute[] {
  const ring = solveCodes(regions, [...regions.keys()]);
  const n = ring.length;
  const k = goats.length;
  if (k === 0) return [];

  let best: { routes: GoatRoute[]; worst: number } | null = null;
  for (let attempt = 0; attempt < attempts; attempt++) {
    // 시드 기반 염소 배치 순서
    const order = [...goats].sort(
      (a, b) =>
        hash32(`${seed}:order:${attempt}:${a.id}`) - hash32(`${seed}:order:${attempt}:${b.id}`),
    );
    // 처음엔 속도 비례로 개수 배분
    const totalSpeed = order.reduce((s, g) => s + g.speedKmh, 0);
    const sizes = order.map((g) => Math.max(1, Math.round((n * g.speedKmh) / totalSpeed)));
    let diff = n - sizes.reduce((s, v) => s + v, 0);
    for (let i = 0; diff !== 0; i = (i + 1) % k) {
      if (diff > 0) {
        sizes[i]!++;
        diff--;
      } else if (sizes[i]! > 1) {
        sizes[i]!--;
        diff++;
      }
    }
    // 링 시작 위치도 시도마다 다르게
    const offset = hash32(`${seed}:offset:${attempt}`) % n;
    const rotated = [...ring.slice(offset), ...ring.slice(0, offset)];

    const cost = (seg: readonly string[], goat: GoatSpec) =>
      worstCycleMinutes(regions, solveCodes(regions, seg), goat);

    // 경계 이동으로 균형 맞추기
    const bounds = [0];
    for (const s of sizes) bounds.push(bounds[bounds.length - 1]! + s);
    const segs = () => order.map((_, i) => rotated.slice(bounds[i]!, bounds[i + 1]!));
    let costs = segs().map((s, i) => cost(s, order[i]!));
    for (let iter = 0; iter < n * 4; iter++) {
      const worst = costs.indexOf(Math.max(...costs));
      let moved = false;
      // 왼쪽 이웃으로 첫 지역을 넘기거나, 오른쪽 이웃으로 마지막 지역을 넘긴다
      for (const dir of [-1, 1] as const) {
        const nb = worst + dir;
        if (nb < 0 || nb >= k) continue;
        const size = bounds[worst + 1]! - bounds[worst]!;
        if (size <= 1) continue;
        const trial = [...bounds];
        if (dir === -1) trial[worst] = trial[worst]! + 1;
        else trial[worst + 1] = trial[worst + 1]! - 1;
        const segW = rotated.slice(trial[worst]!, trial[worst + 1]!);
        const segN = rotated.slice(trial[nb]!, trial[nb + 1]!);
        const cW = cost(segW, order[worst]!);
        const cN = cost(segN, order[nb]!);
        if (Math.max(cW, cN) < costs[worst]!) {
          bounds.splice(0, bounds.length, ...trial);
          costs[worst] = cW;
          costs[nb] = cN;
          moved = true;
          break;
        }
      }
      if (!moved) break;
    }
    costs = segs().map((s, i) => cost(s, order[i]!));
    const worst = Math.max(...costs);
    if (!best || worst < best.worst) {
      best = {
        worst,
        routes: segs().map((s, i) => {
          const tour = solveCodes(regions, s);
          return {
            goatId: order[i]!.id,
            tour,
            ...fitStays(regions, tour, order[i]!, DELIVERY_CYCLE_TARGET_MIN),
          };
        }),
      };
    }
  }
  return best!.routes.sort((a, b) => a.goatId.localeCompare(b.goatId));
}

export function buildPlan(
  regionList: readonly RegionNode[],
  goatList: readonly GoatSpec[],
  seed: string,
): SchedulePlan {
  const regions = new Map(regionList.map((r) => [r.code, r]));
  const goats = new Map(goatList.map((g) => [g.id, g]));
  const delivery = planDelivery(
    regions,
    goatList.filter((g) => g.kind === 'DELIVERY'),
    seed,
  );
  const nationGoat = goatList.find((g) => g.kind === 'ROLLING_NATION');
  const nationTour = nationGoat ? solveCodes(regions, [...regions.keys()]) : [];
  const nation = nationGoat
    ? {
        goatId: nationGoat.id,
        tour: nationTour,
        ...fitStays(regions, nationTour, nationGoat, NATION_BUDGET_MIN),
      }
    : null;
  const provinces = goatList
    .filter((g) => g.kind === 'ROLLING_PROVINCE' && g.scopeCode)
    .map((g) => {
      const tour = solveCodes(
        regions,
        regionList.filter((r) => r.provinceCode === g.scopeCode).map((r) => r.code),
      );
      return { goatId: g.id, tour, ...fitStays(regions, tour, g, PROVINCE_BUDGET_MIN) };
    })
    .filter((r) => r.tour.length > 0);
  return { seed, regions, goats, delivery, nation, provinces };
}

export { tourLength };
