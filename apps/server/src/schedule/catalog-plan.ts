// 카탈로그 + 번들 지역 데이터로 계획을 만든다(시뮬레이터·테스트용, 운영은 DB 값으로 같은 계획을 만든다).
import { readFileSync } from 'node:fs';
import { DELIVERY_GOATS, ROLLING_STATS } from '../catalog/goats.js';
import { buildPlan, type GoatSpec, type RegionNode, type SchedulePlan } from './plan.js';

/** 스케줄 시드. 바꾸면 모든 염소 경로·체류가 바뀐다. */
export const SCHEDULE_SEED = 'meeil-v1';

interface RegionFile {
  provinces: { code: string }[];
  regions: { code: string; provinceCode: string; center: [number, number] }[];
}

export function loadRegionNodes(): { regions: RegionNode[]; provinceCodes: string[] } {
  const url = new URL('../../prisma/data/regions.json', import.meta.url);
  const data = JSON.parse(readFileSync(url, 'utf8')) as RegionFile;
  return {
    regions: data.regions.map((r) => ({
      code: r.code,
      lon: r.center[0],
      lat: r.center[1],
      provinceCode: r.provinceCode,
    })),
    provinceCodes: data.provinces.map((p) => p.code),
  };
}

export function catalogGoatSpecs(provinceCodes: readonly string[]): GoatSpec[] {
  return [
    ...DELIVERY_GOATS.map((g) => ({ ...g, kind: 'DELIVERY' as const })),
    { id: 'rolling-nation', kind: 'ROLLING_NATION', ...ROLLING_STATS.NATION },
    ...provinceCodes.map((code) => ({
      id: `rolling-province-${code}`,
      kind: 'ROLLING_PROVINCE' as const,
      scopeCode: code,
      ...ROLLING_STATS.PROVINCE,
    })),
  ];
}

export function buildCatalogPlan(seed = SCHEDULE_SEED): SchedulePlan {
  const { regions, provinceCodes } = loadRegionNodes();
  return buildPlan(regions, catalogGoatSpecs(provinceCodes), seed);
}
