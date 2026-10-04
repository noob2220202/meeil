// M4 완료 조건: 레벨별 장 주기·참여 규칙 동작 (SPEC 6, 4.2)
import type { FastifyInstance } from 'fastify';
import { afterAll, beforeAll, beforeEach, describe, expect, it } from 'vitest';
import { seed } from '../prisma/seed.js';
import type { Db } from '../src/db.js';
import { periodOf } from '../src/rolling/service.js';
import { ScheduleService } from '../src/schedule/service.js';
import { createTestApp, resetUsers, testClock } from './helpers.js';

const T0 = new Date('2026-10-03T03:00:00Z'); // 토 KST 12:00
const clock = testClock(T0);
let app: FastifyInstance;
let db: Db;

beforeAll(async () => {
  ({ app, db } = await createTestApp({ now: clock.now }));
  await seed(db);
  await db.goatScheduleStop.deleteMany({});
  await new ScheduleService(db).refresh(new Date(T0.getTime() - 3600_000));
});
beforeEach(async () => {
  clock.set(T0);
  await resetUsers(db);
});
afterAll(async () => {
  await app.close();
  await db.$disconnect();
});

interface Res {
  statusCode: number;
  json: <T = any>() => T; // eslint-disable-line @typescript-eslint/no-explicit-any
}
interface U {
  id: string;
  nickname: string;
  token: string;
  get: (url: string) => Promise<Res>;
  post: (url: string, payload?: object) => Promise<Res>;
}

async function loginToken(nickname: string) {
  const r = await app.inject({
    method: 'POST',
    url: '/auth/kakao',
    payload: { accessToken: `kakao-ok:${nickname}` },
  });
  return r.json<{ accessToken: string }>().accessToken;
}

async function makeUser(nickname: string, region: string): Promise<U> {
  const u: U = {
    id: '',
    nickname,
    token: await loginToken(nickname),
    get: (url) =>
      app.inject({ method: 'GET', url, headers: { authorization: `Bearer ${u.token}` } }),
    post: (url, payload = {}) =>
      app.inject({ method: 'POST', url, headers: { authorization: `Bearer ${u.token}` }, payload }),
  };
  await u.post('/me/agreements', { terms: true, privacy: true });
  await u.post('/me/birthdate', { birthDate: '2000-01-01' });
  const me = await app.inject({
    method: 'PUT',
    url: '/me/nickname',
    headers: { authorization: `Bearer ${u.token}` },
    payload: { nickname },
  });
  u.id = me.json<{ id: string }>().id;
  await placeAt(u, region);
  return u;
}

async function placeAt(u: U, region: string) {
  await db.user.update({
    where: { id: u.id },
    data: { lastRegionCode: region, lastRegionReportedAt: clock.now() },
  });
}

async function jump(to: Date | number, ...users: U[]) {
  clock.set(new Date(to));
  for (const u of users) u.token = await loginToken(u.nickname);
}

/** [kind] 롤링 염소가 [at]에 머무는 시 / 그 염소가 안 머무는 같은 도의 시 */
async function rollingStopAt(kind: 'ROLLING_NATION' | 'ROLLING_PROVINCE', at: Date) {
  const stop = await db.goatScheduleStop.findFirstOrThrow({
    where: { arriveAt: { lte: at }, departAt: { gt: at }, goat: { kind } },
    include: { goat: true, region: true },
    orderBy: { regionCode: 'asc' },
  });
  const busy = new Set(
    (
      await db.goatScheduleStop.findMany({
        where: { arriveAt: { lte: at }, departAt: { gt: at }, goat: { kind } },
      })
    ).map((s) => s.regionCode),
  );
  const sameProvince = await db.region.findMany({
    where: { provinceCode: stop.region.provinceCode },
    orderBy: { code: 'asc' },
  });
  const away = sameProvince.find((r) => !busy.has(r.code));
  return { here: stop.regionCode, away: away?.code, provinceCode: stop.region.provinceCode };
}

const entry = (extra: object = {}) => ({
  body: '우리 동네 염소 최고!',
  stickers: [{ id: 'heart', x: 0.5, y: 0.5 }],
  ...extra,
});

describe('장 주기 (SPEC 4.2)', () => {
  it('전국은 월요일 00:00 KST부터 주 1장', () => {
    const p = periodOf('NATION', T0);
    expect(p.start.toISOString()).toBe('2026-09-27T15:00:00.000Z'); // 9/28(월) 00:00 KST
    expect(p.end.toISOString()).toBe('2026-10-04T15:00:00.000Z');
    // 경계: 월 00:00 KST 정각은 새 장
    expect(periodOf('NATION', new Date('2026-10-04T15:00:00Z')).start.toISOString()).toBe(
      '2026-10-04T15:00:00.000Z',
    );
    expect(periodOf('NATION', new Date('2026-10-04T14:59:59Z')).start.toISOString()).toBe(
      '2026-09-27T15:00:00.000Z',
    );
  });

  it('도는 3일 1장, 시는 KST 하루 1장', () => {
    const p = periodOf('PROVINCE', T0);
    expect(p.end.getTime() - p.start.getTime()).toBe(3 * 86400_000);
    expect(p.start <= T0 && T0 < p.end).toBe(true);
    // 3일 주기는 염소 순회 주기와 같은 기준점(2026-01-05 00:00 KST)에서 시작
    expect((p.start.getTime() - Date.UTC(2026, 0, 4, 15)) % (3 * 86400_000)).toBe(0);

    const c = periodOf('CITY', T0);
    expect(c.start.toISOString()).toBe('2026-10-02T15:00:00.000Z');
    expect(c.end.toISOString()).toBe('2026-10-03T15:00:00.000Z');
    // KST 자정 직전(UTC 14:59)은 아직 같은 날
    expect(periodOf('CITY', new Date('2026-10-03T14:59:00Z')).start).toEqual(c.start);
    expect(periodOf('CITY', new Date('2026-10-03T15:00:00Z')).start.toISOString()).toBe(
      '2026-10-03T15:00:00.000Z',
    );
  });

  it('하루가 지나면 시 두루마리는 새 장이 된다', async () => {
    const a = await makeUser('하루지기', '11110');
    const first = (await a.get('/rolling/current?level=CITY')).json();
    expect(first.paper.scopeName).toContain('종로구');
    await jump(T0.getTime() + 86400_000, a);
    await placeAt(a, '11110');
    const second = (await a.get('/rolling/current?level=CITY')).json();
    expect(second.paper.id).not.toBe(first.paper.id);
    expect(new Date(second.paper.periodStart).getTime()).toBe(
      new Date(first.paper.periodEnd).getTime(),
    );
  });
});

describe('참여 규칙 (SPEC 6)', () => {
  it('시 두루마리: 시 롤링 염소는 늘 있어서 바로 참여, 1인 1회', async () => {
    const a = await makeUser('시민하나', '11110');
    const cur = (await a.get('/rolling/current?level=CITY')).json();
    expect(cur.canJoin).toBe(true);
    expect(cur.goatHere).toBe(true);
    expect(cur.entries).toEqual([]); // 빈 장도 정상
    expect(cur.paper.goat.name).toBeTruthy();

    const r = await a.post(`/rolling/${cur.paper.id}/entries`, entry());
    expect(r.statusCode).toBe(201);
    expect(r.json()).toMatchObject({
      body: '우리 동네 염소 최고!',
      mine: true,
      author: { nickname: '시민하나' },
    });

    const again = await a.post(`/rolling/${cur.paper.id}/entries`, entry({ body: '한 번 더' }));
    expect(again.statusCode).toBe(409);
    expect(again.json().error.code).toBe('ALREADY_JOINED');

    const after = (await a.get('/rolling/current?level=CITY')).json();
    expect(after).toMatchObject({ joined: true, canJoin: false, joinBlock: 'ALREADY_JOINED' });
    expect(after.entries).toHaveLength(1);
  });

  it('같은 시 사람끼리 같은 장, 다른 시는 다른 장', async () => {
    const a = await makeUser('종로일', '11110');
    const b = await makeUser('종로이', '11110');
    const c = await makeUser('부산사람', '26110');
    const pa = (await a.get('/rolling/current?level=CITY')).json().paper;
    const pb = (await b.get('/rolling/current?level=CITY')).json().paper;
    const pc = (await c.get('/rolling/current?level=CITY')).json().paper;
    expect(pa.id).toBe(pb.id);
    expect(pc.id).not.toBe(pa.id);

    await a.post(`/rolling/${pa.id}/entries`, entry());
    const seen = (await b.get(`/rolling/${pa.id}`)).json();
    expect(seen.entries).toHaveLength(1);
    expect(seen.entries[0]).toMatchObject({ mine: false, author: { nickname: '종로일' } });
    // 진행 중인 장은 그 지역 사람만
    const outsider = await c.get(`/rolling/${pa.id}`);
    expect(outsider.statusCode).toBe(403);
    expect(outsider.json().error.code).toBe('NOT_IN_SCOPE');
    // 다른 시에서 남의 시 장에 참여할 수 없다
    const cross = await c.post(`/rolling/${pa.id}/entries`, entry());
    expect(cross.statusCode).toBe(409);
    expect(cross.json().error.code).toBe('NOT_IN_SCOPE');
  });

  it('전국 두루마리: 전국 염소가 머무는 시에서만 참여', async () => {
    const { here, away } = await rollingStopAt('ROLLING_NATION', T0);
    const a = await makeUser('전국참여', here);
    const cur = (await a.get('/rolling/current?level=NATION')).json();
    expect(cur.paper.scopeCode).toBe('KR');
    expect(cur.canJoin).toBe(true);
    expect((await a.post(`/rolling/${cur.paper.id}/entries`, entry())).statusCode).toBe(201);

    const b = await makeUser('전국대기', away ?? '11110');
    const wait = (await b.get('/rolling/current?level=NATION')).json();
    expect(wait.paper.id).toBe(cur.paper.id); // 전국은 한 장
    expect(wait).toMatchObject({ canJoin: false, joinBlock: 'NO_GOAT_HERE', goatHere: false });
    expect(wait.entries).toHaveLength(1); // 볼 수는 있다
    const r = await b.post(`/rolling/${cur.paper.id}/entries`, entry());
    expect(r.statusCode).toBe(409);
    expect(r.json().error.code).toBe('NO_GOAT_HERE');
    expect(r.json().error.message).toContain('전국 두루마리 염소가');
  });

  it('도 두루마리: 그 도의 롤링 염소가 머무는 시에서만, 다음 도착 시각을 알려 준다', async () => {
    const { here, away, provinceCode } = await rollingStopAt('ROLLING_PROVINCE', T0);
    const a = await makeUser('도참여', here);
    const cur = (await a.get('/rolling/current?level=PROVINCE')).json();
    expect(cur.paper.scopeCode).toBe(provinceCode);
    expect(cur.canJoin).toBe(true);
    expect((await a.post(`/rolling/${cur.paper.id}/entries`, entry())).statusCode).toBe(201);

    if (away) {
      const b = await makeUser('도대기', away);
      const wait = (await b.get('/rolling/current?level=PROVINCE')).json();
      expect(wait.paper.id).toBe(cur.paper.id);
      expect(wait.joinBlock).toBe('NO_GOAT_HERE');
      expect(new Date(wait.goatNextArriveAt).getTime()).toBeGreaterThan(T0.getTime());
    }
  });

  it('위치가 오래되면(30분 초과) 참여할 수 없다', async () => {
    const a = await makeUser('늦은보고', '11110');
    await jump(T0.getTime() + 31 * 60_000, a);
    const cur = (await a.get('/rolling/current?level=CITY')).json();
    expect(cur.paper.scopeCode).toBe('11110'); // 마지막 시 기준으로 보기는 가능
    expect(cur.joinBlock).toBe('REGION_UNKNOWN');
    const r = await a.post(`/rolling/${cur.paper.id}/entries`, entry());
    expect(r.json().error.code).toBe('REGION_UNKNOWN');
  });

  it('위치를 한 번도 안 알렸으면 도·시 장은 못 보고 전국 장은 본다', async () => {
    const a = await makeUser('무위치', '11110');
    await db.user.update({
      where: { id: a.id },
      data: { lastRegionCode: null, lastRegionReportedAt: null },
    });
    expect((await a.get('/rolling/current?level=CITY')).json().error.code).toBe('REGION_UNKNOWN');
    const n = (await a.get('/rolling/current?level=NATION')).json();
    expect(n).toMatchObject({ canJoin: false, joinBlock: 'REGION_UNKNOWN' });
  });

  it('입력 검증: 빈 글, 200자 초과, 스티커 4개, 사진', async () => {
    const a = await makeUser('검증이', '11110');
    const id = (await a.get('/rolling/current?level=CITY')).json().paper.id;
    const bad = [
      entry({ body: '   ' }),
      entry({ body: '가'.repeat(201) }),
      entry({ stickers: Array.from({ length: 4 }, () => ({ id: 'heart', x: 0.1, y: 0.1 })) }),
      entry({ stickers: [{ id: 'nope', x: 0, y: 0 }] }),
      entry({ photoId: '00000000-0000-7000-8000-000000000000' }),
    ];
    for (const b of bad) {
      const r = await a.post(`/rolling/${id}/entries`, b);
      expect(r.statusCode, JSON.stringify(b).slice(0, 60)).toBe(400);
    }
    expect(
      (await a.post(`/rolling/${id}/entries`, entry({ body: '가'.repeat(200) }))).statusCode,
    ).toBe(201);
  });

  it('참여는 포인트를 쓰지 않는다', async () => {
    const a = await makeUser('무료참여', '11110');
    const before = (await a.get('/me')).json().points;
    const id = (await a.get('/rolling/current?level=CITY')).json().paper.id;
    await a.post(`/rolling/${id}/entries`, entry());
    expect((await a.get('/me')).json().points).toBe(before);
  });
});

describe('마감과 앨범', () => {
  it('마감된 장은 참여자만 보고, 앨범에 영구 보관된다', async () => {
    const a = await makeUser('앨범주인', '11110');
    const b = await makeUser('구경꾼', '11110');
    const paper = (await a.get('/rolling/current?level=CITY')).json().paper;
    await a.post(`/rolling/${paper.id}/entries`, entry());
    expect((await a.get('/rolling/album')).json().papers).toEqual([]); // 진행 중엔 앨범에 없음

    await jump(new Date(paper.periodEnd).getTime() + 60_000, a, b);
    const album = (await a.get('/rolling/album')).json().papers;
    expect(album).toHaveLength(1);
    expect(album[0]).toMatchObject({ id: paper.id, level: 'CITY', entryCount: 1 });

    const view = await a.get(`/rolling/${paper.id}`);
    expect(view.statusCode).toBe(200);
    expect(view.json()).toMatchObject({ closed: true, canJoin: false, joinBlock: 'CLOSED' });

    const late = await a.post(`/rolling/${paper.id}/entries`, entry());
    expect(late.statusCode).toBe(409);
    expect((await b.get(`/rolling/${paper.id}`)).statusCode).toBe(403);
    expect((await b.get('/rolling/album')).json().papers).toEqual([]);

    // 한 달 뒤에도(위치와 무관하게) 그대로
    await jump(T0.getTime() + 40 * 86400_000, a);
    expect((await a.get(`/rolling/${paper.id}`)).json().entries).toHaveLength(1);
  });

  it('/rolling/current/all은 세 레벨을 한 번에 요약한다', async () => {
    const a = await makeUser('요약이', '11110');
    const all = (await a.get('/rolling/current/all')).json();
    expect(Object.keys(all).sort()).toEqual(['CITY', 'NATION', 'PROVINCE']);
    expect(all.CITY).toMatchObject({ canJoin: true, entryCount: 0 });
    expect(all.CITY.entries).toBeUndefined();
    expect(all.PROVINCE.paper.scopeName).toBe('서울');
  });

  it('없는 장, 잘못된 레벨', async () => {
    const a = await makeUser('오류이', '11110');
    expect((await a.get('/rolling/0190f0f0-0000-7000-8000-000000000000')).statusCode).toBe(404);
    expect((await a.get('/rolling/current?level=WORLD')).statusCode).toBe(400);
    expect(
      (await app.inject({ method: 'GET', url: '/rolling/current?level=CITY' })).statusCode,
    ).toBe(401);
  });
});
