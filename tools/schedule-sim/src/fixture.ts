// 사용: pnpm --filter @meeil/tools-schedule-sim fixture ../../apps/mobile/test/fixtures/schedule_20261003_1200kst.json
// 앱 테스트용 스케줄 픽스처: 2026-10-03 12:00 KST 기준 /goats/schedule 응답과 같은 형태
import { writeFileSync } from 'node:fs';
import {
  DELIVERY_GOATS,
  ROLLING_COLORS,
  ROLLING_STATS,
} from '../../../apps/server/src/catalog/goats.ts';
import { buildCatalogPlan, generateStops } from '../../../apps/server/src/schedule/index.ts';
import data from '../../../apps/server/prisma/data/regions.json' with { type: 'json' };
const now = Date.parse('2026-10-03T03:00:00Z');
const from = now - 6 * 3600_000,
  to = now + 48 * 3600_000; // 앱이 받는 범위(48시간)와 같게
const plan = buildCatalogPlan();
const goats = [
  ...DELIVERY_GOATS.map((g) => ({
    id: g.id,
    kind: 'DELIVERY',
    name: g.name,
    scopeCode: null,
    speedKmh: g.speedKmh,
    hatColor: g.hatColor,
    bagColor: g.bagColor,
  })),
  {
    id: 'rolling-nation',
    kind: 'ROLLING_NATION',
    name: '금빛 두루마리',
    scopeCode: null,
    speedKmh: ROLLING_STATS.NATION.speedKmh,
    hatColor: ROLLING_COLORS.NATION.hat,
    bagColor: ROLLING_COLORS.NATION.bag,
  },
  ...data.provinces.map((p: { code: string; shortName: string }) => ({
    id: `rolling-province-${p.code}`,
    kind: 'ROLLING_PROVINCE',
    name: `${p.shortName} 민트 두루마리`,
    scopeCode: p.code,
    speedKmh: ROLLING_STATS.PROVINCE.speedKmh,
    hatColor: ROLLING_COLORS.PROVINCE.hat,
    bagColor: ROLLING_COLORS.PROVINCE.bag,
  })),
];
const stops = generateStops(plan, from, to).map((s) => ({
  goatId: s.goatId,
  regionCode: s.regionCode,
  arriveAt: new Date(s.arriveAt).toISOString(),
  departAt: new Date(s.departAt).toISOString(),
  travelMode: s.travelMode,
  express: false,
}));
writeFileSync(
  process.argv[2]!,
  JSON.stringify({
    serverTime: new Date(now).toISOString(),
    regionVersion: '2026-07',
    from: new Date(from).toISOString(),
    to: new Date(to).toISOString(),
    goats,
    cityGoat: { hatColor: ROLLING_COLORS.CITY.hat, bagColor: ROLLING_COLORS.CITY.bag },
    stops,
  }),
);
console.log('stops', stops.length);
