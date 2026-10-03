import type { FastifyInstance } from 'fastify';
import { afterAll, beforeAll, beforeEach, describe, expect, it } from 'vitest';
import { seed } from '../prisma/seed.js';
import type { Db } from '../src/db.js';
import { judgeRegionReport } from '../src/domain/region-report.js';
import { createTestApp, resetUsers, testClock } from './helpers.js';

const clock = testClock(new Date('2026-10-03T03:00:00Z'));
let app: FastifyInstance;
let db: Db;

beforeAll(async () => {
  ({ app, db } = await createTestApp({ now: clock.now }));
  await seed(db);
  await db.goatScheduleStop.deleteMany({});
});
beforeEach(async () => {
  clock.set(new Date('2026-10-03T03:00:00Z'));
  await resetUsers(db);
});
afterAll(async () => {
  await app.close();
  await db.$disconnect();
});

type ScheduleRes = {
  serverTime: string;
  goats: { id: string; kind: string }[];
  stops: {
    goatId: string;
    regionCode: string;
    arriveAt: string;
    departAt: string;
    travelMode: string;
  }[];
};

describe('GET /goats/schedule', () => {
  it('비어 있으면 스스로 채워서, 지금 앞뒤 정류를 돌려준다', async () => {
    const res = await app.inject({ method: 'GET', url: '/goats/schedule?hours=24' });
    expect(res.statusCode).toBe(200);
    const body = res.json<ScheduleRes>();
    expect(body.serverTime).toBe('2026-10-03T03:00:00.000Z');
    // 배달 12 + 전국 1 + 도 16 (시 롤링은 정류 없음)
    expect(body.goats).toHaveLength(29);
    expect(body.goats.some((g) => g.kind === 'ROLLING_CITY')).toBe(false);

    const now = Date.parse(body.serverTime);
    // 모든 염소는 "지금"을 덮는 정류(머무는 중) 또는 앞뒤 정류(이동 중)를 갖는다
    for (const g of body.goats) {
      const mine = body.stops.filter((s) => s.goatId === g.id);
      expect(
        mine.some((s) => Date.parse(s.arriveAt) <= now),
        g.id,
      ).toBe(true);
      expect(
        mine.some((s) => Date.parse(s.departAt) >= now),
        g.id,
      ).toBe(true);
    }
    // 7일치가 DB에 저장됐다
    const latest = await db.goatScheduleStop.findFirst({ orderBy: { arriveAt: 'desc' } });
    expect(latest!.arriveAt.getTime()).toBeGreaterThan(now + 6 * 24 * 3600_000);
  });

  it('제주 왕복은 배·비행기로 표시된다', async () => {
    const res = await app.inject({ method: 'GET', url: '/goats/schedule?hours=72' });
    const stops = res.json<ScheduleRes>().stops;
    const jeju = stops.filter((s) => s.regionCode === '50110' || s.regionCode === '50130');
    expect(jeju.length).toBeGreaterThan(0);
    expect(stops.some((s) => s.travelMode === 'SEA')).toBe(true);
  });

  it('hours 범위를 벗어나면 400', async () => {
    const res = await app.inject({ method: 'GET', url: '/goats/schedule?hours=500' });
    expect(res.statusCode).toBe(400);
  });

  it('재생성해도 같은 정류(결정적) — 중복 없이 유지', async () => {
    const { ScheduleService } = await import('../src/schedule/service.js');
    const service = new ScheduleService(db);
    await service.refresh(clock.now());
    const snapshot = await db.goatScheduleStop.findMany({
      orderBy: [{ goatId: 'asc' }, { seq: 'asc' }],
    });
    await service.refresh(clock.now());
    const again = await db.goatScheduleStop.findMany({
      orderBy: [{ goatId: 'asc' }, { seq: 'asc' }],
    });
    const strip = (rows: typeof snapshot) => rows.map(({ id: _id, ...rest }) => rest);
    expect(strip(again)).toEqual(strip(snapshot));
  });
});

describe('POST /me/region', () => {
  async function login() {
    const res = await app.inject({
      method: 'POST',
      url: '/auth/kakao',
      payload: { accessToken: 'kakao-ok:region-user' },
    });
    const { accessToken } = res.json<{ accessToken: string }>();
    const headers = { authorization: `Bearer ${accessToken}` };
    return (payload: object) => app.inject({ method: 'POST', url: '/me/region', headers, payload });
  }

  it('지역 코드를 받아 현재·가입 지역과 방문 기록을 남긴다', async () => {
    const report = await login();
    const res = await report({ regionCode: '11110' });
    expect(res.json()).toEqual({ accepted: true, reason: null, regionCode: '11110' });
    const user = (await db.user.findFirst())!;
    expect(user.lastRegionCode).toBe('11110');
    expect(user.homeRegionCode).toBe('11110');
    expect(await db.regionVisit.count({ where: { userId: user.id } })).toBe(1);
  });

  it('가짜 GPS는 반영하지 않는다', async () => {
    const report = await login();
    const res = await report({ regionCode: '11110', mocked: true });
    expect(res.json()).toMatchObject({ accepted: false, reason: 'MOCKED' });
    expect((await db.user.findFirst())!.lastRegionCode).toBeNull();
  });

  it('서울에서 10분 만에 제주는 거부, 하루 뒤는 허용', async () => {
    const report = await login();
    await report({ regionCode: '11110' });
    clock.set(new Date(clock.now().getTime() + 10 * 60_000));
    expect((await report({ regionCode: '50110' })).json()).toMatchObject({
      accepted: false,
      reason: 'TOO_FAST',
      regionCode: '11110',
    });
    clock.set(new Date(clock.now().getTime() + 24 * 3600_000));
    const later = await login(); // access 토큰(1시간)이 만료됐으므로 다시 로그인
    expect((await later({ regionCode: '50110' })).json()).toMatchObject({ accepted: true });
    const user = (await db.user.findFirst())!;
    // 가입 지역은 처음 값 유지
    expect(user.homeRegionCode).toBe('11110');
    expect(await db.regionVisit.count({ where: { userId: user.id } })).toBe(2);
    expect(await db.userRegionReport.count({ where: { userId: user.id, accepted: false } })).toBe(
      1,
    );
  });

  it('없는 지역·좌표 형태 입력은 400', async () => {
    const report = await login();
    expect((await report({ regionCode: '99999' })).statusCode).toBe(400);
    expect((await report({ regionCode: '37.5,127.0' })).statusCode).toBe(400);
  });
});

describe('judgeRegionReport', () => {
  const seoul = { lon: 126.97, lat: 37.6 };
  const suwon = { lon: 127.0, lat: 37.27 };
  it('옆 동네로의 짧은 이동은 허용(대표점 거리 보정)', () => {
    const now = new Date('2026-10-03T00:05:00Z');
    expect(
      judgeRegionReport({
        mocked: false,
        last: { ...seoul, at: new Date('2026-10-03T00:00:00Z') },
        next: suwon,
        now,
      }),
    ).toBeNull();
  });
});
