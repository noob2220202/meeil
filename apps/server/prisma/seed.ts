// 기준 데이터 시드: 지역(시도·시), 염소, 편지지, 업적. 여러 번 실행해도 안전(upsert).
import 'dotenv/config';
import { readFile } from 'node:fs/promises';
import { ACHIEVEMENTS } from '../src/catalog/achievements.js';
import { DELIVERY_GOATS, ROLLING_COLORS, ROLLING_STATS } from '../src/catalog/goats.js';
import { STATIONERY } from '../src/catalog/stationery.js';
import { createDb, type Db } from '../src/db.js';
import type { Prisma } from '../src/generated/prisma/client.js';
import { loadEnv } from '../src/env.js';

interface RegionSeed {
  version: string;
  provinces: { code: string; name: string; shortName: string }[];
  regions: {
    code: string;
    name: string;
    fullName: string;
    provinceCode: string;
    center: [number, number];
    neighbors: string[];
  }[];
}

export async function loadRegionSeed(): Promise<RegionSeed> {
  const url = new URL('./data/regions.json', import.meta.url);
  return JSON.parse(await readFile(url, 'utf8')) as RegionSeed;
}

export async function seed(db: Db): Promise<void> {
  const data = await loadRegionSeed();

  for (const p of data.provinces) {
    const row = { name: p.name, shortName: p.shortName, version: data.version };
    await db.province.upsert({
      where: { code: p.code },
      create: { code: p.code, ...row },
      update: row,
    });
  }
  for (const r of data.regions) {
    const row = {
      name: r.name,
      fullName: r.fullName,
      provinceCode: r.provinceCode,
      lon: r.center[0],
      lat: r.center[1],
      neighbors: r.neighbors,
      version: data.version,
      active: true,
    };
    await db.region.upsert({
      where: { code: r.code },
      create: { code: r.code, ...row },
      update: row,
    });
  }
  // 개편으로 사라진 지역은 비활성화(기존 편지·사용자 참조 보존)
  await db.region.updateMany({
    where: { code: { notIn: data.regions.map((r) => r.code) } },
    data: { active: false },
  });

  const goats: Prisma.GoatCreateInput[] = [
    ...DELIVERY_GOATS.map((g, i) => ({
      id: g.id,
      kind: 'DELIVERY' as const,
      name: g.name,
      speedKmh: g.speedKmh,
      stayMinMin: g.stayMinMin,
      stayMaxMin: g.stayMaxMin,
      hatColor: g.hatColor,
      bagColor: g.bagColor,
      sortOrder: i,
    })),
    {
      id: 'rolling-nation',
      kind: 'ROLLING_NATION',
      name: '금빛 두루마리',
      ...ROLLING_STATS.NATION,
      hatColor: ROLLING_COLORS.NATION.hat,
      bagColor: ROLLING_COLORS.NATION.bag,
      sortOrder: 100,
    },
    ...data.provinces.map((p, i) => ({
      id: `rolling-province-${p.code}`,
      kind: 'ROLLING_PROVINCE' as const,
      name: `${p.shortName} 민트 두루마리`,
      scopeCode: p.code,
      ...ROLLING_STATS.PROVINCE,
      hatColor: ROLLING_COLORS.PROVINCE.hat,
      bagColor: ROLLING_COLORS.PROVINCE.bag,
      sortOrder: 200 + i,
    })),
    ...data.regions.map((r, i) => ({
      id: `rolling-city-${r.code}`,
      kind: 'ROLLING_CITY' as const,
      name: `${r.name} 분홍 두루마리`,
      scopeCode: r.code,
      ...ROLLING_STATS.CITY,
      hatColor: ROLLING_COLORS.CITY.hat,
      bagColor: ROLLING_COLORS.CITY.bag,
      sortOrder: 1000 + i,
    })),
  ];
  for (const g of goats) {
    const { id, ...rest } = g;
    await db.goat.upsert({ where: { id }, create: g, update: rest });
  }
  await db.goat.updateMany({
    where: { id: { notIn: goats.map((g) => g.id) } },
    data: { active: false },
  });

  for (const [i, s] of STATIONERY.entries()) {
    const row = { name: s.name, unlockHint: s.unlockHint, isDefault: s.isDefault, sortOrder: i };
    await db.stationery.upsert({ where: { id: s.id }, create: { id: s.id, ...row }, update: row });
  }
  for (const [i, a] of ACHIEVEMENTS.entries()) {
    const row = {
      name: a.name,
      description: a.description,
      rewardPoints: a.rewardPoints,
      titleText: a.titleText ?? null,
      unlocksStationeryId: a.unlocksStationeryId ?? null,
      sortOrder: i,
    };
    await db.achievement.upsert({ where: { id: a.id }, create: { id: a.id, ...row }, update: row });
  }
}

if (import.meta.url === `file://${process.argv[1]}`) {
  const env = loadEnv();
  const db = createDb(env.DATABASE_URL);
  try {
    await seed(db);
    const [regions, goats] = await Promise.all([db.region.count(), db.goat.count()]);
    console.log(`시드 완료: 지역 ${regions}곳, 염소 ${goats}마리`);
  } finally {
    await db.$disconnect();
  }
}
