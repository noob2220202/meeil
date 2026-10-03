// 경계 데이터 가공용 순수 함수 모음 (테스트 대상)

/** 일반구(예: 수원시장안구)를 상위 시로 합친 "시" 단위 코드·이름을 돌려준다. */
export function toCity(sggCode: string, sggName: string): { code: string; name: string } {
  const m = /^(.+시)(.+구)$/.exec(sggName);
  if (m && m[1]) {
    return { code: `${sggCode.slice(0, 4)}0`, name: m[1] };
  }
  return { code: sggCode, name: sggName };
}

const PROVINCE_SHORT: Record<string, string> = {
  서울특별시: '서울',
  부산광역시: '부산',
  대구광역시: '대구',
  인천광역시: '인천',
  광주광역시: '광주',
  대전광역시: '대전',
  울산광역시: '울산',
  세종특별자치시: '세종',
  경기도: '경기',
  강원특별자치도: '강원',
  충청북도: '충북',
  충청남도: '충남',
  전북특별자치도: '전북',
  전라남도: '전남',
  전남광주통합특별시: '전남광주',
  경상북도: '경북',
  경상남도: '경남',
  제주특별자치도: '제주',
};

export function provinceShortName(fullName: string): string {
  const short = PROVINCE_SHORT[fullName];
  if (!short) throw new Error(`알 수 없는 시도 이름: ${fullName}`);
  return short;
}

/** 세종시처럼 시도와 시가 같은 곳은 "세종", 나머지는 "서울 종로구" 형태. */
export function displayName(provinceShort: string, cityName: string): string {
  if (cityName.startsWith(provinceShort)) return cityName;
  return `${provinceShort} ${cityName}`;
}

type TopoGeometry = { arcs?: unknown; properties?: Record<string, unknown> };

function collectArcIds(arcs: unknown, out: Set<number>): void {
  if (typeof arcs === 'number') {
    out.add(arcs < 0 ? ~arcs : arcs);
    return;
  }
  if (Array.isArray(arcs)) for (const a of arcs) collectArcIds(a, out);
}

/** TopoJSON에서 같은 arc를 공유하는 지오메트리끼리 이웃으로 본다. */
export function neighborsFromTopology(
  geometries: TopoGeometry[],
  idKey: string,
): Map<string, string[]> {
  const arcOwners = new Map<number, Set<string>>();
  const ids: string[] = [];
  for (const g of geometries) {
    const id = String(g.properties?.[idKey]);
    ids.push(id);
    const arcIds = new Set<number>();
    collectArcIds(g.arcs, arcIds);
    for (const a of arcIds) {
      let owners = arcOwners.get(a);
      if (!owners) arcOwners.set(a, (owners = new Set()));
      owners.add(id);
    }
  }
  const result = new Map<string, Set<string>>(ids.map((id) => [id, new Set()]));
  for (const owners of arcOwners.values()) {
    if (owners.size < 2) continue;
    for (const a of owners) for (const b of owners) if (a !== b) result.get(a)?.add(b);
  }
  return new Map([...result].map(([k, v]) => [k, [...v].sort()]));
}

/** 좌표를 소수 4자리(약 10m)로 반올림하고 연속 중복점을 제거한다. */
export function roundRing(ring: number[][]): number[] {
  const flat: number[] = [];
  let px = NaN;
  let py = NaN;
  for (const pt of ring) {
    const x = Math.round((pt[0] ?? 0) * 1e4) / 1e4;
    const y = Math.round((pt[1] ?? 0) * 1e4) / 1e4;
    if (x === px && y === py) continue;
    flat.push(x, y);
    px = x;
    py = y;
  }
  return flat;
}

/** 두 경위도 점 사이 거리(km). */
export function haversineKm(a: readonly [number, number], b: readonly [number, number]): number {
  const R = 6371;
  const rad = Math.PI / 180;
  const dLat = (b[1] - a[1]) * rad;
  const dLon = (b[0] - a[0]) * rad;
  const h =
    Math.sin(dLat / 2) ** 2 + Math.cos(a[1] * rad) * Math.cos(b[1] * rad) * Math.sin(dLon / 2) ** 2;
  return 2 * R * Math.asin(Math.sqrt(h));
}

/**
 * 경계를 공유하는 이웃이 없는 섬 지역은 중심점이 가장 가까운 지역 k곳을 이웃으로 붙인다(양방향).
 * 다리·뱃길로 이어진 곳(거제, 영종 등)을 염소 경로에서 고립시키지 않기 위함.
 */
export function addIslandNeighbors(
  neighbors: Map<string, string[]>,
  centers: Map<string, readonly [number, number]>,
  k = 2,
): Map<string, string[]> {
  const out = new Map([...neighbors].map(([key, v]) => [key, new Set(v)]));
  for (const [code, set] of out) {
    if (set.size > 0) continue;
    const c = centers.get(code);
    if (!c) continue;
    const nearest = [...centers]
      .filter(([other]) => other !== code)
      .map(([other, oc]) => [other, haversineKm(c, oc)] as const)
      .sort((a, b) => a[1] - b[1])
      .slice(0, k);
    for (const [other] of nearest) {
      set.add(other);
      out.get(other)?.add(code);
    }
  }
  return new Map([...out].map(([key, v]) => [key, [...v].sort()]));
}

/**
 * 이웃 그래프가 여러 덩어리로 나뉘어 있으면(제주처럼 섬끼리만 이어진 경우)
 * 가장 큰 덩어리에 가장 가까운 지역 쌍을 이어 하나로 만든다.
 */
export function connectComponents(
  neighbors: Map<string, string[]>,
  centers: Map<string, readonly [number, number]>,
): Map<string, string[]> {
  const out = new Map([...neighbors].map(([k, v]) => [k, new Set(v)]));
  for (;;) {
    const comps: string[][] = [];
    const seen = new Set<string>();
    for (const start of out.keys()) {
      if (seen.has(start)) continue;
      const comp: string[] = [];
      const stack = [start];
      seen.add(start);
      while (stack.length) {
        const cur = stack.pop()!;
        comp.push(cur);
        for (const n of out.get(cur) ?? []) {
          if (!seen.has(n)) {
            seen.add(n);
            stack.push(n);
          }
        }
      }
      comps.push(comp);
    }
    if (comps.length <= 1) break;
    comps.sort((a, b) => b.length - a.length);
    const main = comps[0]!;
    const small = comps[comps.length - 1]!;
    let best: [string, string, number] | null = null;
    for (const a of small) {
      const ca = centers.get(a);
      if (!ca) continue;
      for (const b of main) {
        const cb = centers.get(b);
        if (!cb) continue;
        const d = haversineKm(ca, cb);
        if (!best || d < best[2]) best = [a, b, d];
      }
    }
    if (!best) break;
    out.get(best[0])!.add(best[1]);
    out.get(best[1])!.add(best[0]);
  }
  return new Map([...out].map(([k, v]) => [k, [...v].sort()]));
}

/** 짝수-홀수 규칙 point-in-polygon. ring은 [x,y,x,y,...] */
export function pointInRing(x: number, y: number, ring: readonly number[]): boolean {
  let inside = false;
  const n = ring.length / 2;
  for (let i = 0, j = n - 1; i < n; j = i++) {
    const xi = ring[2 * i]!;
    const yi = ring[2 * i + 1]!;
    const xj = ring[2 * j]!;
    const yj = ring[2 * j + 1]!;
    if (yi > y !== yj > y && x < ((xj - xi) * (y - yi)) / (yj - yi) + xi) inside = !inside;
  }
  return inside;
}
