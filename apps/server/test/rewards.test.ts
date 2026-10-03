// M5 완료 조건: 포인트 증감·해금 시나리오 (SPEC 7)
import { createPublicKey, generateKeyPairSync, randomUUID, sign } from 'node:crypto';
import type { FastifyInstance } from 'fastify';
import { afterAll, beforeAll, beforeEach, describe, expect, it } from 'vitest';
import { seed } from '../prisma/seed.js';
import type { Db } from '../src/db.js';
import type { AdKeySource } from '../src/rewards/ads.js';
import { ScheduleService } from '../src/schedule/service.js';
import { createTestApp, resetUsers, testClock } from './helpers.js';

const T0 = new Date('2026-10-03T03:00:00Z'); // 토 KST 12:00
const DAY = 86400_000;
const clock = testClock(T0);
let app: FastifyInstance;
let db: Db;

// 테스트용 AdMob 서명 키
const { privateKey, publicKey } = generateKeyPairSync('ec', { namedCurve: 'prime256v1' });
const KEY_ID = '3335741209';
const adKeys: AdKeySource = {
  get: async (id) =>
    id === KEY_ID ? createPublicKey(publicKey.export({ type: 'spki', format: 'pem' })) : null,
};

beforeAll(async () => {
  ({ app, db } = await createTestApp({ now: clock.now, adKeys }));
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
  put: (url: string, payload?: object) => Promise<Res>;
}

async function loginToken(nickname: string) {
  const r = await app.inject({
    method: 'POST',
    url: '/auth/kakao',
    payload: { accessToken: `kakao-ok:${nickname}` },
  });
  return r.json<{ accessToken: string }>().accessToken;
}

async function makeUser(nickname: string, region = '11110', birthDate = '2000-01-01'): Promise<U> {
  const auth = () => ({ authorization: `Bearer ${u.token}` });
  const u: U = {
    id: '',
    nickname,
    token: await loginToken(nickname),
    get: (url) => app.inject({ method: 'GET', url, headers: auth() }),
    post: (url, payload = {}) => app.inject({ method: 'POST', url, headers: auth(), payload }),
    put: (url, payload = {}) => app.inject({ method: 'PUT', url, headers: auth(), payload }),
  };
  await u.post('/me/agreements', { terms: true, privacy: true });
  await u.post('/me/birthdate', { birthDate });
  u.id = (await u.put('/me/nickname', { nickname })).json<{ id: string }>().id;
  await placeAt(u, region);
  return u;
}

async function placeAt(u: U, region: string) {
  await db.user.update({
    where: { id: u.id },
    data: { lastRegionCode: region, lastRegionReportedAt: clock.now() },
  });
}

async function jump(to: number | Date | string, ...users: U[]) {
  clock.set(new Date(to));
  for (const u of users) u.token = await loginToken(u.nickname);
}

const balance = async (u: U) =>
  (await u.get('/me')).json<{ pointsBalance: number }>().pointsBalance;

/** 원장 합계 = 잔액 캐시 (서버 원장이 권위) */
async function expectLedgerConsistent(u: U) {
  const agg = await db.pointsLedger.aggregate({ where: { userId: u.id }, _sum: { delta: true } });
  expect(agg._sum.delta ?? 0).toBe(await balance(u));
}

function ssvQuery(
  userId: string,
  opts: { tx?: string; ts?: number; unit?: string; tamper?: boolean } = {},
) {
  const msg = [
    'ad_network=5450213213286189855',
    `ad_unit=${opts.unit ?? '5224354917'}`,
    'custom_data=meeil',
    'reward_amount=2',
    'reward_item=%ED%92%80',
    `timestamp=${opts.ts ?? clock.now().getTime()}`,
    `transaction_id=${opts.tx ?? randomUUID().replaceAll('-', '')}`,
    `user_id=${userId}`,
  ].join('&');
  const sig = sign('sha256', Buffer.from(msg), { key: privateKey, dsaEncoding: 'der' }).toString(
    'base64url',
  );
  const signed = opts.tamper ? msg.replace('reward_amount=2', 'reward_amount=200') : msg;
  return `${signed}&signature=${sig}&key_id=${KEY_ID}`;
}

const callback = (q: string) => app.inject({ method: 'GET', url: `/ads/reward-callback?${q}` });

describe('가입·원장', () => {
  it('가입하면 5P와 기본 편지지, 원장 합계가 잔액과 같다', async () => {
    const a = await makeUser('원장이');
    expect(await balance(a)).toBe(5);
    const st = (await a.get('/stationery')).json().stationery;
    expect(st.filter((s: { owned: boolean }) => s.owned).map((s: { id: string }) => s.id)).toEqual([
      'cream',
    ]);
    const h = (await a.get('/points/history')).json();
    expect(h.entries).toMatchObject([
      { delta: 5, balanceAfter: 5, reason: 'SIGNUP_BONUS', label: '가입 선물' },
    ]);
    await expectLedgerConsistent(a);
  });

  it('/me는 생년월일 대신 광고 미성년 여부만 알려 준다', async () => {
    const teen = await makeUser('청소년', '11110', '2010-05-05');
    const adult = await makeUser('어른이', '11110', '1990-05-05');
    const t = (await teen.get('/me')).json();
    expect(t.ads).toEqual({ underAge: true });
    expect(JSON.stringify(t)).not.toContain('2010');
    expect((await adult.get('/me')).json().ads).toEqual({ underAge: false });
  });
});

describe('출석 (+3P, 7일 연속 +5P)', () => {
  it('하루 한 번만, 다음 날 연속, 7일째 보너스 + 업적(줄노트 해금)', async () => {
    const a = await makeUser('출석왕');
    const first = (await a.post('/attendance')).json();
    expect(first).toMatchObject({ checkedIn: true, streak: 1, checkedToday: true, totalDays: 1 });
    expect(first.rewards).toEqual([{ reason: 'ATTENDANCE', points: 3 }]);
    expect(await balance(a)).toBe(8);

    const again = (await a.post('/attendance')).json();
    expect(again).toMatchObject({ checkedIn: false, streak: 1, rewards: [] });
    expect(await balance(a)).toBe(8);

    for (let d = 1; d <= 6; d++) {
      await jump(T0.getTime() + d * DAY, a);
      const r = (await a.post('/attendance')).json();
      expect(r.streak).toBe(d + 1);
      if (d === 6) {
        expect(r.rewards).toEqual([
          { reason: 'ATTENDANCE', points: 3 },
          { reason: 'ATTENDANCE_STREAK', points: 5 },
        ]);
      }
    }
    // 5 + 3*7 + 5(연속) + 3(업적 출석 7일)
    expect(await balance(a)).toBe(5 + 21 + 5 + 3);
    const st = (await a.get('/stationery')).json().stationery;
    expect(st.find((s: { id: string }) => s.id === 'lined').owned).toBe(true);

    const unseen = (await a.get('/achievements/unseen')).json().achievements;
    expect(unseen).toMatchObject([
      { id: 'attend-7', rewardPoints: 3, stationeryId: 'lined', stationeryName: '줄노트' },
    ]);
    await a.post('/achievements/seen', { ids: ['attend-7'] });
    expect((await a.get('/achievements/unseen')).json().achievements).toEqual([]);
    await expectLedgerConsistent(a);
  });

  it('하루 빠지면 연속이 끊긴다', async () => {
    const a = await makeUser('띄엄이');
    await a.post('/attendance');
    await jump(T0.getTime() + DAY, a);
    await a.post('/attendance');
    await jump(T0.getTime() + 3 * DAY, a);
    const s = (await a.get('/attendance')).json();
    expect(s).toMatchObject({ checkedToday: false, streak: 0 });
    expect((await a.post('/attendance')).json().streak).toBe(1);
  });

  it('날짜 경계는 KST 자정', async () => {
    const a = await makeUser('자정이');
    await jump('2026-10-03T14:59:00Z', a); // 23:59 KST
    await a.post('/attendance');
    await jump('2026-10-03T15:00:00Z', a); // 다음 날 00:00 KST
    const r = (await a.post('/attendance')).json();
    expect(r).toMatchObject({ checkedIn: true, streak: 2, today: '2026-10-04' });
    expect((await a.get('/attendance?month=2026-10')).json().days).toEqual([
      '2026-10-03',
      '2026-10-04',
    ]);
  });
});

describe('보상형 광고 SSV (+2P, 하루 5회)', () => {
  it('서명이 맞는 콜백만, 같은 거래는 한 번만 지급', async () => {
    const a = await makeUser('광고러');
    const tx = 'abc123';
    const ok = await callback(ssvQuery(a.id, { tx }));
    expect(ok.statusCode).toBe(200);
    expect(ok.json()).toEqual({ ok: true, granted: true });
    expect(await balance(a)).toBe(7);

    expect((await callback(ssvQuery(a.id, { tx }))).json()).toEqual({ ok: true, granted: false });
    expect(await balance(a)).toBe(7);

    expect((await callback(ssvQuery(a.id, { tamper: true }))).statusCode).toBe(403);
    expect(
      (await callback(ssvQuery(a.id).replace(`key_id=${KEY_ID}`, 'key_id=1'))).statusCode,
    ).toBe(403);
    expect((await callback('ad_network=1&user_id=x')).statusCode).toBe(403);
    expect(
      (await callback(ssvQuery(a.id, { ts: clock.now().getTime() - 2 * DAY }))).statusCode,
    ).toBe(400);
    // 콘솔 확인 요청(쿼리 없음)
    expect((await app.inject({ method: 'GET', url: '/ads/reward-callback' })).statusCode).toBe(200);
    expect(await balance(a)).toBe(7);
    await expectLedgerConsistent(a);
  });

  it('하루 5회 상한, 다음 날(KST) 다시 열린다', async () => {
    const a = await makeUser('광고왕');
    for (let i = 0; i < 6; i++) await callback(ssvQuery(a.id));
    expect(await balance(a)).toBe(5 + 10);
    expect((await a.get('/ads/status')).json()).toEqual({
      rewardPoints: 2,
      dailyMax: 5,
      todayCount: 5,
      remaining: 0,
    });
    await jump(T0.getTime() + DAY, a);
    expect((await a.get('/ads/status')).json().remaining).toBe(5);
    await callback(ssvQuery(a.id));
    expect(await balance(a)).toBe(17);
  });

  it('동시에 여러 콜백이 와도 상한을 넘지 않는다', async () => {
    const a = await makeUser('동시광고');
    await Promise.all(Array.from({ length: 10 }, () => callback(ssvQuery(a.id))));
    expect(await balance(a)).toBe(5 + 10);
    await expectLedgerConsistent(a);
  });

  it('모르는 사용자 → 400, 개발용 지급도 같은 상한', async () => {
    expect((await callback(ssvQuery(randomUUID()))).statusCode).toBe(400);
    const a = await makeUser('개발광고');
    const r = (await a.post('/ads/dev-reward')).json();
    expect(r).toMatchObject({ ok: true, granted: true, remaining: 4 });
  });
});

describe('편지·업적·칭호', () => {
  async function goatRegion() {
    const stop = await db.goatScheduleStop.findFirstOrThrow({
      where: { arriveAt: { lte: T0 }, departAt: { gt: T0 }, goat: { kind: 'DELIVERY' } },
    });
    return stop.regionCode;
  }
  const letter = (to: string, extra: object = {}) => ({
    mode: 'DIRECT',
    recipientId: to,
    body: '안녕!',
    stationeryId: 'cream',
    stickers: [],
    clientRequestId: randomUUID(),
    ...extra,
  });

  it('편지 1통 -1P, 첫 편지 업적 +2P와 칭호, 칭호 달기', async () => {
    const here = await goatRegion();
    const a = await makeUser('편지꾼', here);
    const b = await makeUser('받는이', here);
    const r = await a.post('/letters', letter(b.id));
    expect(r.statusCode).toBe(201);
    expect(await balance(a)).toBe(5 - 1 + 2);

    const list = (await a.get('/achievements')).json();
    const first = list.achievements.find((x: { id: string }) => x.id === 'first-letter');
    expect(first).toMatchObject({
      achieved: true,
      titleText: '새내기 편지꾼',
      progress: { current: 1, target: 1 },
    });
    const city10 = list.achievements.find((x: { id: string }) => x.id === 'visit-city-10');
    expect(city10).toMatchObject({ achieved: false, progress: { current: 0, target: 10 } });
    const allGoats = list.achievements.find((x: { id: string }) => x.id === 'meet-all-goats');
    expect(allGoats.progress).toEqual({ current: 1, target: 12 });

    // 얻지 못한 칭호는 못 단다
    expect((await a.put('/me/title', { achievementId: 'attend-30' })).statusCode).toBe(400);
    expect((await a.put('/me/title', { achievementId: 'first-letter' })).statusCode).toBe(200);
    expect((await a.get('/me')).json().title).toBe('새내기 편지꾼');
    const sent = (await a.get('/letters/sent')).json().letters[0];
    expect(sent.sender.title).toBe('새내기 편지꾼');
    await a.put('/me/title', { achievementId: null });
    expect((await a.get('/me')).json().title).toBeNull();
    await expectLedgerConsistent(a);
  });

  it('포인트가 없으면 편지를 못 맡기고 아무것도 남지 않는다', async () => {
    const here = await goatRegion();
    const a = await makeUser('빈지갑', here);
    const b = await makeUser('받을이', here);
    await db.user.update({ where: { id: a.id }, data: { pointsBalance: 0 } });
    await db.pointsLedger.create({
      data: {
        userId: a.id,
        delta: -5,
        balanceAfter: 0,
        reason: 'ADMIN_ADJUST',
        idempotencyKey: `t:${a.id}`,
      },
    });
    const r = await a.post('/letters', letter(b.id));
    expect(r.statusCode).toBe(409);
    expect(r.json().error.code).toBe('INSUFFICIENT_POINTS');
    expect(await db.letter.count({ where: { senderId: a.id } })).toBe(0);
    expect(await balance(a)).toBe(0);
    await expectLedgerConsistent(a);
  });

  it('10개 시 방문 → 하늘 구름 편지지, 제주 방문 업적', async () => {
    const a = await makeUser('여행가');
    const regions = await db.region.findMany({
      where: { provinceCode: '11' },
      take: 9,
      orderBy: { code: 'asc' },
    });
    await db.regionVisit.createMany({
      data: regions.map((r) => ({ userId: a.id, regionCode: r.code })),
    });
    // 10번째 시를 보고(서울 안이라 속도 검사 통과)
    await db.user.update({
      where: { id: a.id },
      data: { lastRegionCode: null, lastRegionReportedAt: null },
    });
    const tenth = await db.region.findFirstOrThrow({
      where: { provinceCode: '11', code: { notIn: regions.map((r) => r.code) } },
    });
    expect((await a.post('/me/region', { regionCode: tenth.code })).json().accepted).toBe(true);
    const st = (await a.get('/stationery')).json().stationery;
    expect(st.find((s: { id: string }) => s.id === 'sky-cloud').owned).toBe(true);
    expect(await balance(a)).toBe(5 + 3);

    await jump(T0.getTime() + DAY, a);
    const jeju = await db.region.findFirstOrThrow({ where: { provinceCode: '50' } });
    await a.post('/me/region', { regionCode: jeju.code });
    const ids = (await a.get('/achievements/unseen'))
      .json()
      .achievements.map((x: { id: string }) => x.id);
    expect(ids).toEqual(expect.arrayContaining(['visit-city-10', 'visit-jeju']));
    // 같은 시 다시 보고해도 중복 지급 없음
    const before = await balance(a);
    await jump(T0.getTime() + 2 * DAY, a);
    await a.post('/me/region', { regionCode: jeju.code });
    expect(await balance(a)).toBe(before);
    await expectLedgerConsistent(a);
  });

  it('롤링페이퍼 첫 참여 업적', async () => {
    const a = await makeUser('두루미');
    const id = (await a.get('/rolling/current?level=CITY')).json().paper.id;
    await a.post(`/rolling/${id}/entries`, { body: '안녕', stickers: [] });
    const unseen = (await a.get('/achievements/unseen')).json().achievements;
    expect(unseen.map((x: { id: string }) => x.id)).toEqual(['first-rolling']);
    expect(await balance(a)).toBe(7);
  });

  it('포인트 내역은 최신순·페이지로', async () => {
    const a = await makeUser('내역이');
    for (let d = 0; d < 35; d++) {
      await db.pointsLedger.create({
        data: {
          userId: a.id,
          delta: 1,
          balanceAfter: 6 + d,
          reason: 'ADMIN_ADJUST',
          idempotencyKey: `h:${a.id}:${d}`,
          createdAt: new Date(T0.getTime() + (d + 1) * 1000),
        },
      });
    }
    const p1 = (await a.get('/points/history')).json();
    expect(p1.entries).toHaveLength(30);
    expect(p1.entries[0].balanceAfter).toBe(40);
    const p2 = (await a.get(`/points/history?cursor=${p1.nextCursor}`)).json();
    expect(p2.entries).toHaveLength(6);
    expect(p2.nextCursor).toBeNull();
    expect(p2.entries.at(-1).reason).toBe('SIGNUP_BONUS');
  });
});
