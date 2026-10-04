export type LonLat = readonly [number, number];

export function haversineKm(a: LonLat, b: LonLat): number {
  const R = 6371;
  const rad = Math.PI / 180;
  const dLat = (b[1] - a[1]) * rad;
  const dLon = (b[0] - a[0]) * rad;
  const h =
    Math.sin(dLat / 2) ** 2 + Math.cos(a[1] * rad) * Math.cos(b[1] * rad) * Math.sin(dLon / 2) ** 2;
  return 2 * R * Math.asin(Math.sqrt(h));
}

/**
 * 섬 그룹. 그룹이 다른 두 지역 사이 이동은 배/비행기로 본다(SPEC 4.1 도서 지역).
 * 다리로 이어진 섬(거제·남해·영종·완도·진도)은 본토 취급.
 */
const ISLAND_GROUP: Record<string, string> = {
  '50110': 'jeju',
  '50130': 'jeju',
  '47940': 'ulleung',
  '28720': 'ongjin',
};

export function islandGroup(regionCode: string): string {
  return ISLAND_GROUP[regionCode] ?? 'mainland';
}

export function isSeaLeg(a: string, b: string): boolean {
  return islandGroup(a) !== islandGroup(b);
}
