import type { FastifyInstance } from 'fastify';
import { afterAll, beforeAll, describe, expect, it } from 'vitest';
import type { Db } from '../src/db.js';
import { seed } from '../prisma/seed.js';
import { createTestApp } from './helpers.js';

let app: FastifyInstance;
let db: Db;

beforeAll(async () => {
  ({ app, db } = await createTestApp());
  await seed(db);
});

afterAll(async () => {
  await app.close();
  await db.$disconnect();
});

describe('GET /health', () => {
  it('DB 연결이 살아 있으면 ok', async () => {
    const res = await app.inject({ method: 'GET', url: '/health' });
    expect(res.statusCode).toBe(200);
    expect(res.json()).toMatchObject({ ok: true });
  });
});

describe('404', () => {
  it('공통 오류 형태로 응답한다', async () => {
    const res = await app.inject({ method: 'GET', url: '/nope' });
    expect(res.statusCode).toBe(404);
    expect(res.json()).toEqual({ error: { code: 'NOT_FOUND', message: '찾을 수 없어요.' } });
  });
});

describe('GET /regions', () => {
  it('시드된 지역 테이블을 돌려준다', async () => {
    const res = await app.inject({ method: 'GET', url: '/regions' });
    expect(res.statusCode).toBe(200);
    const body = res.json<{
      version: string;
      provinces: { code: string }[];
      regions: {
        code: string;
        provinceCode: string;
        neighbors: string[];
        lon: number;
        lat: number;
      }[];
    }>();
    expect(body.version).toBe('2026-07');
    expect(body.provinces.length).toBe(16);
    expect(body.regions.length).toBeGreaterThanOrEqual(220);

    const codes = new Set(body.regions.map((r) => r.code));
    const provinceCodes = new Set(body.provinces.map((p) => p.code));
    for (const r of body.regions) {
      expect(provinceCodes.has(r.provinceCode)).toBe(true);
      // 모든 지역은 이웃이 있고(섬은 가까운 지역으로 연결), 이웃 코드는 실제 지역이다
      expect(r.neighbors.length).toBeGreaterThan(0);
      for (const n of r.neighbors) expect(codes.has(n)).toBe(true);
      // 대표점은 대한민국 범위 안
      expect(r.lon).toBeGreaterThan(124);
      expect(r.lon).toBeLessThan(132);
      expect(r.lat).toBeGreaterThan(33);
      expect(r.lat).toBeLessThan(39);
    }
  });
});

describe('시드 데이터', () => {
  it('배달 염소 12마리, 전국 롤링 1마리, 시도·시 롤링 염소가 지역 수만큼 있다', async () => {
    const [delivery, nation, province, city, provinces, regions] = await Promise.all([
      db.goat.count({ where: { kind: 'DELIVERY', active: true } }),
      db.goat.count({ where: { kind: 'ROLLING_NATION', active: true } }),
      db.goat.count({ where: { kind: 'ROLLING_PROVINCE', active: true } }),
      db.goat.count({ where: { kind: 'ROLLING_CITY', active: true } }),
      db.province.count(),
      db.region.count({ where: { active: true } }),
    ]);
    expect(delivery).toBe(12);
    expect(nation).toBe(1);
    expect(province).toBe(provinces);
    expect(city).toBe(regions);
  });

  it('편지지 3종 중 기본은 크림 하나', async () => {
    const all = await db.stationery.findMany();
    expect(all).toHaveLength(3);
    expect(all.filter((s) => s.isDefault).map((s) => s.id)).toEqual(['cream']);
  });
});
