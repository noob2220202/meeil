// 위치 보고 검증 (SPEC 8): 기기가 판정한 지역 코드만 받는다. 좌표는 받지 않는다.
import { haversineKm } from '../schedule/geo.js';

/** 이보다 빠르게 이동했다는 보고는 가짜 GPS로 보고 무시한다(시속 km) */
export const MAX_PLAUSIBLE_KMH = 300;

export type ReportRejectReason = 'MOCKED' | 'TOO_FAST';

export function judgeRegionReport(input: {
  mocked: boolean;
  last: { lon: number; lat: number; at: Date } | null;
  next: { lon: number; lat: number };
  now: Date;
}): ReportRejectReason | null {
  if (input.mocked) return 'MOCKED';
  if (!input.last) return null;
  const km = haversineKm([input.last.lon, input.last.lat], [input.next.lon, input.next.lat]);
  if (km < 1) return null;
  // 대표점 사이 거리라 실제보다 조금 멀 수 있으므로 최소 10분은 걸린 것으로 본다
  const hours = Math.max(1 / 6, (input.now.getTime() - input.last.at.getTime()) / 3_600_000);
  return km / hours > MAX_PLAUSIBLE_KMH ? 'TOO_FAST' : null;
}
