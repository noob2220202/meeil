// 행정동 경계(admdongkor) → 시 단위 지역 데이터 생성
// 실행: pnpm --filter @meeil/tools-regions build:regions
import { createHash } from 'node:crypto';
import { existsSync } from 'node:fs';
import { mkdir, readFile, writeFile, copyFile } from 'node:fs/promises';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';
import mapshaper from 'mapshaper';
import {
  addIslandNeighbors,
  displayName,
  neighborsFromTopology,
  provinceShortName,
  roundRing,
  toCity,
} from './lib.js';

const SOURCE_COMMIT = 'dd1881663fcabc69b81393604e91ebf3a4202e9a';
const SOURCE_VERSION = 'ver20260701';
const SOURCE_URL = `https://raw.githubusercontent.com/vuski/admdongkor/${SOURCE_COMMIT}/${SOURCE_VERSION}/HangJeongDong_${SOURCE_VERSION}.geojson`;
/** 지역 테이블 버전. 행정구역 개편 시 올린다. */
export const REGION_VERSION = '2026-07';

const ULLEUNG = '47940';

const here = dirname(fileURLToPath(import.meta.url));
const root = join(here, '..');
const repo = join(root, '..', '..');
const cacheFile = join(root, '.cache', `${SOURCE_VERSION}.geojson`);
const outDir = join(root, 'out');

type Feature = {
  type: 'Feature';
  properties: Record<string, string>;
  geometry: { type: string; coordinates: unknown };
};

async function loadSource(): Promise<{ features: Feature[] }> {
  if (!existsSync(cacheFile)) {
    console.log(`다운로드: ${SOURCE_URL}`);
    const res = await fetch(SOURCE_URL);
    if (!res.ok) throw new Error(`다운로드 실패 ${res.status}`);
    await mkdir(dirname(cacheFile), { recursive: true });
    await writeFile(cacheFile, Buffer.from(await res.arrayBuffer()));
  }
  const buf = await readFile(cacheFile);
  console.log(`원본 sha256=${createHash('sha256').update(buf).digest('hex')}`);
  return JSON.parse(buf.toString('utf8')) as { features: Feature[] };
}

async function run(commands: string, input: Record<string, unknown>) {
  return (await mapshaper.applyCommands(commands, input)) as Record<string, string>;
}

async function main() {
  const src = await loadSource();
  const rawFeatures = src.features.map((f) => ({ ...f, properties: { ...f.properties } }));
  for (const f of src.features) {
    const p = f.properties;
    const city = toCity(p.sgg ?? '', p.sggnm ?? '');
    f.properties = { code: city.code, name: city.name, sido: p.sido ?? '', sidonm: p.sidonm ?? '' };
  }

  // 시 단위로 병합 → 단순화(토폴로지 유지)
  const topo = JSON.parse(
    (
      await run(
        '-i in.json -dissolve code copy-fields=name,sido,sidonm ' +
          '-simplify weighted 3% keep-shapes ' +
          '' +
          '-clean -o out.json format=topojson precision=0.0001',
        { 'in.json': { type: 'FeatureCollection', features: src.features } },
      )
    )['out.json'] ?? '{}',
  ) as {
    objects: Record<
      string,
      { geometries: { arcs?: unknown; properties?: Record<string, unknown> }[] }
    >;
  };

  const layer = Object.values(topo.objects)[0];
  if (!layer) throw new Error('topology 결과 없음');

  const geo = JSON.parse(
    (await run('-i in.json -o out.json format=geojson precision=0.0001', { 'in.json': topo }))[
      'out.json'
    ] ?? '{}',
  ) as { features: Feature[] };
  const centers = JSON.parse(
    (
      await run('-i in.json -points inner -o out.json format=geojson precision=0.0001', {
        'in.json': topo,
      })
    )['out.json'] ?? '{}',
  ) as { features: Feature[] };
  const centerByCode = new Map(
    centers.features.map((f) => [
      String(f.properties.code),
      f.geometry.coordinates as [number, number],
    ]),
  );

  const neighbors = addIslandNeighbors(
    neighborsFromTopology(layer.geometries, 'code'),
    centerByCode,
  );

  // 독도는 단순화 과정에서 사라지므로 원본에서 따로 뽑아 울릉군에 붙인다.
  const dokdo = JSON.parse(
    (
      await run(
        '-i in.json -filter "sgg === \'47940\'" -explode -filter "this.centroidX > 131.5" ' +
          '-simplify interval=15 -o out.json format=geojson precision=0.0001',
        { 'in.json': { type: 'FeatureCollection', features: rawFeatures } },
      )
    )['out.json'] ?? '{}',
  ) as { features: Feature[] };
  const dokdoPolys = dokdo.features.map((f) => f.geometry.coordinates as number[][][]);
  if (dokdoPolys.length === 0) throw new Error('독도 폴리곤을 찾지 못함');

  const provinces = new Map<string, { code: string; name: string; shortName: string }>();
  const regions = geo.features
    .map((f) => {
      const p = f.properties;
      const code = String(p.code);
      const provinceCode = String(p.sido);
      const shortName = provinceShortName(String(p.sidonm));
      provinces.set(provinceCode, { code: provinceCode, name: String(p.sidonm), shortName });
      const polys =
        f.geometry.type === 'Polygon'
          ? [f.geometry.coordinates as number[][][]]
          : (f.geometry.coordinates as number[][][][]);
      const center = centerByCode.get(code);
      if (!center) throw new Error(`중심점 없음: ${code}`);
      return {
        code,
        name: String(p.name),
        fullName: displayName(shortName, String(p.name)),
        provinceCode,
        center: [center[0], center[1]] as [number, number],
        neighbors: neighbors.get(code) ?? [],
        polygons: [...polys, ...(code === ULLEUNG ? dokdoPolys : [])].map((poly) =>
          poly.map(roundRing),
        ),
      };
    })
    .sort((a, b) => a.code.localeCompare(b.code));

  const provinceList = [...provinces.values()].sort((a, b) => a.code.localeCompare(b.code));
  const pointCount = regions.reduce(
    (s, r) => s + r.polygons.flat().reduce((t, ring) => t + ring.length / 2, 0),
    0,
  );
  console.log(`시 ${regions.length}곳, 시도 ${provinceList.length}곳, 정점 ${pointCount}개`);

  const meta = {
    version: REGION_VERSION,
    source: `vuski/admdongkor@${SOURCE_COMMIT.slice(0, 7)} ${SOURCE_VERSION} (통계청 SGIS, 공공누리 1유형 / CC BY 4.0)`,
  };
  const mobile = { ...meta, provinces: provinceList, regions };
  const seed = {
    ...meta,
    provinces: provinceList,
    regions: regions.map(({ polygons: _p, ...rest }) => rest),
  };

  await mkdir(outDir, { recursive: true });
  const mobileOut = join(outDir, 'regions.json');
  const seedOut = join(outDir, 'regions.seed.json');
  await writeFile(mobileOut, JSON.stringify(mobile));
  await writeFile(seedOut, JSON.stringify(seed, null, 1));

  const mobileDest = join(repo, 'apps/mobile/assets/map/regions.json');
  const seedDest = join(repo, 'apps/server/prisma/data/regions.json');
  for (const [from, to] of [
    [mobileOut, mobileDest],
    [seedOut, seedDest],
  ] as const) {
    await mkdir(dirname(to), { recursive: true });
    await copyFile(from, to);
    console.log(`→ ${to}`);
  }
}

await main();
