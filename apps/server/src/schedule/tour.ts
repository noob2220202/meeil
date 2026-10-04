// 순회 경로: 최근접 이웃으로 시작해 2-opt로 다듬는다(SPEC 4.3). 닫힌 순회(마지막 → 처음).

export type DistFn = (a: number, b: number) => number;

export function tourLength(tour: readonly number[], dist: DistFn): number {
  let sum = 0;
  for (let i = 0; i < tour.length; i++) sum += dist(tour[i]!, tour[(i + 1) % tour.length]!);
  return sum;
}

export function nearestNeighborTour(
  nodes: readonly number[],
  dist: DistFn,
  start: number,
): number[] {
  const left = new Set(nodes);
  const tour = [start];
  left.delete(start);
  let cur = start;
  while (left.size > 0) {
    let best = -1;
    let bestD = Infinity;
    for (const n of left) {
      const d = dist(cur, n);
      if (d < bestD || (d === bestD && n < best)) {
        best = n;
        bestD = d;
      }
    }
    tour.push(best);
    left.delete(best);
    cur = best;
  }
  return tour;
}

/** 2-opt 개선. 더 이상 줄지 않거나 반복 한도에 닿으면 멈춘다(결정적). */
export function twoOpt(tour: number[], dist: DistFn, maxPasses = 50): number[] {
  const t = [...tour];
  const n = t.length;
  if (n < 4) return t;
  for (let pass = 0; pass < maxPasses; pass++) {
    let improved = false;
    for (let i = 0; i < n - 1; i++) {
      for (let k = i + 2; k < n; k++) {
        if (i === 0 && k === n - 1) continue;
        const a = t[i]!;
        const b = t[i + 1]!;
        const c = t[k]!;
        const d = t[(k + 1) % n]!;
        const delta = dist(a, c) + dist(b, d) - dist(a, b) - dist(c, d);
        if (delta < -1e-9) {
          // i+1..k 구간 뒤집기
          for (let lo = i + 1, hi = k; lo < hi; lo++, hi--) {
            const tmp = t[lo]!;
            t[lo] = t[hi]!;
            t[hi] = tmp;
          }
          improved = true;
        }
      }
    }
    if (!improved) break;
  }
  return t;
}

/** 최근접 이웃 + 2-opt 닫힌 순회. 시작점은 가장 작은 인덱스(결정적). */
export function solveTour(nodes: readonly number[], dist: DistFn): number[] {
  if (nodes.length <= 2) return [...nodes];
  const start = Math.min(...nodes);
  return twoOpt(nearestNeighborTour(nodes, dist, start), dist);
}
