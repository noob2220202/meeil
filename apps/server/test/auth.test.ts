import type { FastifyInstance } from 'fastify';
import { afterAll, beforeAll, beforeEach, describe, expect, it } from 'vitest';
import { seed } from '../prisma/seed.js';
import type { Db } from '../src/db.js';
import { createTestApp, resetUsers, testClock } from './helpers.js';

const clock = testClock();
let app: FastifyInstance;
let db: Db;

beforeAll(async () => {
  ({ app, db } = await createTestApp({ now: clock.now }));
  await seed(db);
});
beforeEach(async () => {
  clock.set(new Date('2026-10-03T03:00:00Z')); // KST 2026-10-03 12:00
  await resetUsers(db);
});
afterAll(async () => {
  await app.close();
  await db.$disconnect();
});

type LoginRes = {
  accessToken: string;
  refreshToken: string;
  isNew: boolean;
  me: { id: string; onboarding: { completed: boolean } };
};

async function login(token = 'kakao-ok:1001'): Promise<LoginRes> {
  const res = await app.inject({
    method: 'POST',
    url: '/auth/kakao',
    payload: { accessToken: token },
  });
  expect(res.statusCode).toBe(200);
  return res.json<LoginRes>();
}

function as(accessToken: string) {
  const headers = { authorization: `Bearer ${accessToken}` };
  return {
    get: (url: string) => app.inject({ method: 'GET', url, headers }),
    post: (url: string, payload: object) => app.inject({ method: 'POST', url, headers, payload }),
    put: (url: string, payload: object) => app.inject({ method: 'PUT', url, headers, payload }),
  };
}

async function onboard(accessToken: string, nickname = '메롱염소') {
  const u = as(accessToken);
  expect((await u.post('/me/agreements', { terms: true, privacy: true })).statusCode).toBe(200);
  expect((await u.post('/me/birthdate', { birthDate: '2000-05-05' })).statusCode).toBe(200);
  const res = await u.put('/me/nickname', { nickname });
  expect(res.statusCode).toBe(200);
  return res.json<{
    nickname: string;
    pointsBalance: number;
    onboarding: { completed: boolean };
  }>();
}

describe('소셜 로그인', () => {
  it('처음이면 가입, 다시 오면 같은 계정으로 로그인', async () => {
    const first = await login();
    expect(first.isNew).toBe(true);
    expect(first.me.onboarding.completed).toBe(false);
    const again = await login();
    expect(again.isNew).toBe(false);
    expect(again.me.id).toBe(first.me.id);
  });

  it('카카오와 구글은 서로 다른 계정', async () => {
    const k = await login('kakao-ok:same');
    const g = await app.inject({
      method: 'POST',
      url: '/auth/google',
      payload: { idToken: 'google-ok:same' },
    });
    expect(g.json<LoginRes>().me.id).not.toBe(k.me.id);
  });

  it('검증 실패한 토큰은 401', async () => {
    const res = await app.inject({
      method: 'POST',
      url: '/auth/kakao',
      payload: { accessToken: 'forged-token-123' },
    });
    expect(res.statusCode).toBe(401);
    expect(res.json()).toMatchObject({ error: { code: 'SOCIAL_TOKEN_INVALID' } });
  });

  it('입력 형식이 틀리면 400', async () => {
    const res = await app.inject({ method: 'POST', url: '/auth/kakao', payload: {} });
    expect(res.statusCode).toBe(400);
    expect(res.json()).toMatchObject({ error: { code: 'VALIDATION' } });
  });

  it('정지(BANNED) 계정은 로그인 불가', async () => {
    const { me } = await login();
    await db.user.update({ where: { id: me.id }, data: { status: 'BANNED' } });
    const res = await app.inject({
      method: 'POST',
      url: '/auth/kakao',
      payload: { accessToken: 'kakao-ok:1001' },
    });
    expect(res.statusCode).toBe(403);
  });
});

describe('GET /me', () => {
  it('토큰 없으면 401', async () => {
    expect((await app.inject({ method: 'GET', url: '/me' })).statusCode).toBe(401);
    const bad = await as('nope').get('/me');
    expect(bad.statusCode).toBe(401);
  });

  it('생년월일·소셜 ID는 응답에 없다', async () => {
    const { accessToken } = await login('kakao-ok:secret-provider-id');
    await onboard(accessToken);
    const res = await as(accessToken).get('/me');
    expect(res.statusCode).toBe(200);
    expect(res.body).not.toContain('2000-05-05');
    expect(res.body).not.toContain('"birthDate"');
    expect(res.body).not.toContain('secret-provider-id');
    expect(res.body).not.toContain('provider');
  });

  it('access 토큰은 1시간 뒤 만료', async () => {
    const { accessToken } = await login();
    clock.set(new Date(clock.now().getTime() + 61 * 60 * 1000));
    expect((await as(accessToken).get('/me')).statusCode).toBe(401);
  });
});

describe('가입 절차', () => {
  it('약관 → 생년월일 → 닉네임을 마치면 완료되고 가입 보너스 5P·기본 편지지를 받는다', async () => {
    const { accessToken, me } = await login();
    const done = await onboard(accessToken);
    expect(done.onboarding.completed).toBe(true);
    expect(done.pointsBalance).toBe(5);
    const ledger = await db.pointsLedger.findMany({ where: { userId: me.id } });
    expect(ledger).toHaveLength(1);
    expect(ledger[0]).toMatchObject({ delta: 5, balanceAfter: 5, reason: 'SIGNUP_BONUS' });
    const stationery = await db.userStationery.findMany({ where: { userId: me.id } });
    expect(stationery.map((s) => s.stationeryId)).toEqual(['cream']);
  });

  it('가입 보너스는 한 번만 (약관 재동의해도 중복 지급 없음)', async () => {
    const { accessToken, me } = await login();
    await onboard(accessToken);
    await as(accessToken).post('/me/agreements', { terms: true, privacy: true });
    expect(await db.pointsLedger.count({ where: { userId: me.id } })).toBe(1);
  });

  it('필수 약관에 동의하지 않으면 400', async () => {
    const { accessToken } = await login();
    const res = await as(accessToken).post('/me/agreements', { terms: true, privacy: false });
    expect(res.statusCode).toBe(400);
  });

  it('만 14세 미만이면 403, 계정과 소셜 연결을 지운다', async () => {
    const { accessToken, me } = await login();
    await as(accessToken).post('/me/agreements', { terms: true, privacy: true });
    // KST 2026-10-03 기준 2012-10-04생은 만 13세
    const res = await as(accessToken).post('/me/birthdate', { birthDate: '2012-10-04' });
    expect(res.statusCode).toBe(403);
    expect(res.json()).toMatchObject({ error: { code: 'UNDER_AGE' } });
    expect(await db.user.findUnique({ where: { id: me.id } })).toBeNull();
    expect(await db.authIdentity.count()).toBe(0);
    expect((await as(accessToken).get('/me')).statusCode).toBe(401);
  });

  it('만 14세 생일 당일(KST)은 가입 가능', async () => {
    const { accessToken } = await login();
    const res = await as(accessToken).post('/me/birthdate', { birthDate: '2012-10-03' });
    expect(res.statusCode).toBe(200);
  });

  it('생년월일은 한 번만 입력', async () => {
    const { accessToken } = await login();
    await as(accessToken).post('/me/birthdate', { birthDate: '2000-01-01' });
    const res = await as(accessToken).post('/me/birthdate', { birthDate: '1990-01-01' });
    expect(res.statusCode).toBe(409);
  });

  it('없는 날짜는 400', async () => {
    const { accessToken } = await login();
    const res = await as(accessToken).post('/me/birthdate', { birthDate: '2001-02-29' });
    expect(res.statusCode).toBe(400);
  });
});

describe('닉네임', () => {
  it('중복 확인은 대소문자를 무시한다', async () => {
    const a = await login('kakao-ok:a');
    await onboard(a.accessToken, 'GoatKing');
    const b = await login('kakao-ok:b');
    const check = await as(b.accessToken).get(
      `/nicknames/check?nick=${encodeURIComponent('goatking')}`,
    );
    expect(check.json()).toMatchObject({ available: false, reason: 'TAKEN' });
    const put = await as(b.accessToken).put('/me/nickname', { nickname: 'GOATKING' });
    expect(put.statusCode).toBe(409);
    expect(put.json()).toMatchObject({ error: { code: 'NICKNAME_TAKEN' } });
  });

  it('금칙어·형식 오류는 확인 단계에서 이유를 알려준다', async () => {
    const { accessToken } = await login();
    const banned = await as(accessToken).get(`/nicknames/check?nick=${encodeURIComponent('시발')}`);
    expect(banned.json()).toMatchObject({ available: false, reason: 'BANNED' });
    const ok = await as(accessToken).get(`/nicknames/check?nick=${encodeURIComponent('뽀얀염소')}`);
    expect(ok.json()).toMatchObject({ available: true });
    const put = await as(accessToken).put('/me/nickname', { nickname: '가' });
    expect(put.statusCode).toBe(400);
    expect(put.json()).toMatchObject({ error: { code: 'NICKNAME_LENGTH' } });
  });

  it('30일에 한 번만 바꿀 수 있다', async () => {
    const { accessToken } = await login();
    await onboard(accessToken, '첫닉네임');
    const soon = await as(accessToken).put('/me/nickname', { nickname: '두번째' });
    expect(soon.statusCode).toBe(409);
    expect(soon.json()).toMatchObject({ error: { code: 'NICKNAME_TOO_SOON' } });

    clock.advanceDays(30);
    // 30일이 지나 다시 로그인(access 만료) 후 변경
    const { accessToken: fresh } = await login();
    const later = await as(fresh).put('/me/nickname', { nickname: '두번째' });
    expect(later.statusCode).toBe(200);
    expect(later.json()).toMatchObject({ nickname: '두번째' });
  });
});

describe('토큰 회전', () => {
  it('refresh는 새 토큰을 주고, 쓴 토큰을 다시 쓰면 계열 전체를 폐기한다', async () => {
    const first = await login();
    const r1 = await app.inject({
      method: 'POST',
      url: '/auth/refresh',
      payload: { refreshToken: first.refreshToken },
    });
    expect(r1.statusCode).toBe(200);
    const second = r1.json<{ accessToken: string; refreshToken: string }>();
    expect(second.refreshToken).not.toBe(first.refreshToken);
    expect((await as(second.accessToken).get('/me')).statusCode).toBe(200);

    // 탈취 시나리오: 옛 토큰 재사용 → 거부, 새 토큰도 폐기됨
    const replay = await app.inject({
      method: 'POST',
      url: '/auth/refresh',
      payload: { refreshToken: first.refreshToken },
    });
    expect(replay.statusCode).toBe(401);
    const afterReplay = await app.inject({
      method: 'POST',
      url: '/auth/refresh',
      payload: { refreshToken: second.refreshToken },
    });
    expect(afterReplay.statusCode).toBe(401);
  });

  it('refresh 토큰은 30일 뒤 만료', async () => {
    const { refreshToken } = await login();
    clock.advanceDays(31);
    const res = await app.inject({
      method: 'POST',
      url: '/auth/refresh',
      payload: { refreshToken },
    });
    expect(res.statusCode).toBe(401);
  });

  it('로그아웃하면 refresh 불가', async () => {
    const { refreshToken } = await login();
    const out = await app.inject({
      method: 'POST',
      url: '/auth/logout',
      payload: { refreshToken },
    });
    expect(out.statusCode).toBe(204);
    const res = await app.inject({
      method: 'POST',
      url: '/auth/refresh',
      payload: { refreshToken },
    });
    expect(res.statusCode).toBe(401);
  });
});

describe('요청 제한', () => {
  it('로그인은 IP당 분당 20회까지', async () => {
    const { app: limited, db: limitedDb } = await createTestApp({ rateLimit: true });
    const codes: number[] = [];
    for (let i = 0; i < 21; i++) {
      const res = await limited.inject({ method: 'POST', url: '/auth/kakao', payload: {} });
      codes.push(res.statusCode);
    }
    expect(codes.slice(0, 20).every((c) => c === 400)).toBe(true);
    expect(codes[20]).toBe(429);
    await limited.close();
    await limitedDb.$disconnect();
  });
});

describe('개발용 로그인', () => {
  it('켜져 있으면 /auth/dev로 가입할 수 있다', async () => {
    const res = await app.inject({
      method: 'POST',
      url: '/auth/dev',
      payload: { devId: 'tester1' },
    });
    expect(res.statusCode).toBe(200);
  });

  it('꺼져 있으면 라우트가 없다', async () => {
    const { app: off, db: offDb } = await createTestApp({ devLogin: false });
    const res = await off.inject({ method: 'POST', url: '/auth/dev', payload: { devId: 'x' } });
    expect(res.statusCode).toBe(404);
    await off.close();
    await offDb.$disconnect();
  });
});
