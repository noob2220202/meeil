// M9 보안 점검: 라우트 인증 목록 · 개인정보 노출 · 보안 헤더 · 위치 규칙 (SPEC 14, docs/SECURITY.md)
import { randomUUID } from 'node:crypto';
import type { FastifyInstance } from 'fastify';
import { SignJWT } from 'jose';
import { afterAll, beforeAll, beforeEach, describe, expect, it } from 'vitest';
import { seed } from '../prisma/seed.js';
import { hashPassword, newTotpSecret, seal, totpCode } from '../src/admin/crypto.js';
import type { Db } from '../src/db.js';
import { adminSecretKey, loadEnv } from '../src/env.js';
import { ScheduleService } from '../src/schedule/service.js';
import { createTestApp, resetUsers, testClock } from './helpers.js';
import { userKit } from './users.js';

const T0 = new Date('2026-10-03T03:00:00Z');
const clock = testClock(T0);
let app: FastifyInstance;
let db: Db;
const { makeUser, jump } = userKit(
  () => app,
  () => db,
  clock,
);

beforeAll(async () => {
  ({ app, db } = await createTestApp({ now: clock.now }));
  await seed(db);
  await db.goatScheduleStop.deleteMany({});
  await new ScheduleService(db).refresh(new Date(T0.getTime() - 3600_000));
});
beforeEach(async () => {
  clock.set(T0);
  await resetUsers(db);
  await db.adminUser.deleteMany({});
});
afterAll(async () => {
  await app.close();
  await db.$disconnect();
});

/**
 * 토큰 없이 부를 수 있는 라우트의 전부. 새 공개 라우트를 만들면 여기에 이유와 함께 적어야
 * 테스트가 통과한다 — 인증을 깜빡한 라우트가 조용히 배포되지 않게 하는 장치.
 */
const PUBLIC = new Set([
  'GET /health', // 헬스 체크
  'GET /regions', // 공개 지역 목록(경계 데이터)
  'GET /goats/schedule', // 염소 스케줄은 모두에게 같은 공개 정보
  'POST /auth/kakao',
  'POST /auth/google',
  'POST /auth/dev', // 개발 전용(운영 env에서 AUTH_DEV_LOGIN=true면 부팅 거부)
  'POST /auth/refresh', // refresh 토큰 자체가 자격
  'POST /auth/logout', // refresh 토큰 자체가 자격
  'POST /client-errors', // 크래시 요약(로그인 전 오류 포함), 요청 제한
  'GET /legal/:doc', // 스토어 등록 URL
  'GET /account/delete', // 앱 없이 삭제 요청(스토어 정책)
  'GET /account/delete.js',
  'POST /account/delete-request', // 요청 제한 5회/시간, 운영자가 확인 후 처리
  'GET /ads/reward-callback', // AdMob SSV: ECDSA 서명으로 검증
  'POST /admin/login', // 비밀번호 + TOTP
  'GET /media/*', // 로컬 저장소 전용, 서명 URL로 검증
  'OPTIONS *', // CORS preflight
]);

const urlFor = (url: string) => url.replace(/:[a-zA-Z]+/g, randomUUID()).replace('*', 'x');
const call = (method: string, url: string, token?: string) =>
  app.inject({
    method: method as 'GET',
    url: urlFor(url),
    headers: token ? { authorization: `Bearer ${token}` } : {},
    ...(method === 'GET' || method === 'DELETE' ? {} : { payload: {} }),
  });

const secretKey = adminSecretKey(
  loadEnv({
    ...process.env,
    DATABASE_URL: 'postgres://x@localhost/x',
    JWT_SECRET: process.env.JWT_SECRET ?? 'test-secret-0123456789abcdef0123456789',
  }),
);

async function adminToken(): Promise<string> {
  const secret = newTotpSecret();
  await db.adminUser.create({
    data: {
      username: 'sec',
      role: 'ADMIN',
      passwordHash: await hashPassword('correct horse battery'),
      totpSecret: seal(secret, secretKey),
    },
  });
  const r = await app.inject({
    method: 'POST',
    url: '/admin/login',
    payload: {
      username: 'sec',
      password: 'correct horse battery',
      totp: totpCode(secret, clock.now().getTime()),
    },
  });
  return r.json<{ token: string }>().token;
}

describe('라우트 인증 목록', () => {
  it('공개 목록에 없는 모든 라우트는 토큰 없이 401', async () => {
    await app.ready();
    const routes = app.routeList.map((r) => `${r.method} ${r.url}`);
    expect(routes.length).toBeGreaterThan(60);
    // 공개 목록이 실제 라우트와 어긋나면(지운 라우트가 남아 있으면) 목록도 고친다
    for (const p of PUBLIC) expect(routes, p).toContain(p);

    const leaks: string[] = [];
    for (const r of app.routeList) {
      const key = `${r.method} ${r.url}`;
      if (PUBLIC.has(key)) continue;
      const res = await call(r.method, r.url);
      if (res.statusCode !== 401) leaks.push(`${key} → ${res.statusCode}`);
    }
    expect(leaks).toEqual([]);
  });

  it('위조·만료·다른 용도 토큰은 거절하고, 사용자·관리자 토큰은 서로의 라우트를 못 쓴다', async () => {
    await app.ready();
    const u = await makeUser('보안염소');
    const admin = await adminToken();
    const userRoutes = app.routeList.filter(
      (r) => !PUBLIC.has(`${r.method} ${r.url}`) && !r.url.startsWith('/admin'),
    );
    const adminRoutes = app.routeList.filter(
      (r) => !PUBLIC.has(`${r.method} ${r.url}`) && r.url.startsWith('/admin'),
    );

    // 다른 키로 서명한 토큰, alg=none 토큰
    const forged = await new SignJWT({ typ: 'access' })
      .setProtectedHeader({ alg: 'HS256' })
      .setSubject(u.id)
      .setIssuedAt()
      .setExpirationTime('1h')
      .sign(new TextEncoder().encode('not-the-real-secret-0123456789abcdef'));
    const none = `${Buffer.from('{"alg":"none","typ":"JWT"}').toString('base64url')}.${Buffer.from(
      JSON.stringify({ sub: u.id, exp: Math.floor(Date.now() / 1000) + 3600 }),
    ).toString('base64url')}.`;

    for (const r of userRoutes) {
      expect((await call(r.method, r.url, admin)).statusCode, `admin→${r.url}`).toBe(401);
      expect((await call(r.method, r.url, forged)).statusCode, `forged→${r.url}`).toBe(401);
      expect((await call(r.method, r.url, none)).statusCode, `none→${r.url}`).toBe(401);
    }
    for (const r of adminRoutes) {
      expect((await call(r.method, r.url, u.token)).statusCode, `user→${r.url}`).toBe(401);
    }

    // access 토큰 1시간 만료
    const stale = u.token;
    clock.set(new Date(T0.getTime() + 2 * 3600_000));
    expect((await call('GET', '/me', stale)).statusCode).toBe(401);
  });
});

describe('개인정보 노출', () => {
  /** 응답 어디에도 나오면 안 되는 표식 */
  const BIRTH = '1987-06-05';
  const PROVIDER_ID = 'provider-secret-7f3a';
  const FORBIDDEN_KEYS = ['"birthDate"', '"providerUserId"', '"provider"', '"email"', '"lat"'];

  it('사용자가 부를 수 있는 모든 GET 응답에 생년월일·소셜 ID·이메일이 없다', async () => {
    await app.ready();
    const stop = await db.goatScheduleStop.findFirstOrThrow({
      where: { arriveAt: { lte: T0 }, departAt: { gt: T0 }, goat: { kind: 'DELIVERY' } },
    });
    const a = await makeUser('비밀염소', stop.regionCode);
    const b = await makeUser('친구염소', stop.regionCode);
    for (const u of [a, b]) {
      await db.user.update({
        where: { id: u.id },
        data: { birthDate: new Date(`${BIRTH}T00:00:00Z`) },
      });
      await db.authIdentity.updateMany({
        where: { userId: u.id },
        data: { providerUserId: `${PROVIDER_ID}-${u.id}` },
      });
    }
    const sent = await a.post('/letters', {
      mode: 'DIRECT',
      recipientId: b.id,
      body: '비밀은 지켜 줄게!',
      stationeryId: 'cream',
      stickers: [],
      clientRequestId: randomUUID(),
    });
    expect(sent.statusCode, sent.body).toBe(201);
    const letterId = sent.json<{ id: string }>().id;
    await jump(T0.getTime() + 80 * 3600_000, a, b);
    const rolling = (await a.get('/rolling/current')).json<{ id?: string }>();

    const gets = app.routeList.filter(
      (r) => r.method === 'GET' && !PUBLIC.has(`GET ${r.url}`) && !r.url.startsWith('/admin'),
    );
    const checked: string[] = [];
    for (const r of gets) {
      const urls = [r.url.replace(':userId', b.id).replace(':id', letterId)];
      if (r.url === '/rolling/:id' && rolling.id) urls[0] = `/rolling/${rolling.id}`;
      if (r.url === '/users/search') urls[0] = '/users/search?q=염소';
      if (r.url === '/nicknames/check') urls[0] = '/nicknames/check?nickname=새염소';
      for (const u of [a, b]) {
        for (const url of urls) {
          const res = await u.get(url);
          checked.push(`${url} ${res.statusCode}`);
          for (const k of FORBIDDEN_KEYS) expect(res.body, `${url} ${k}`).not.toContain(k);
          expect(res.body, url).not.toContain(BIRTH);
          expect(res.body, url).not.toContain(PROVIDER_ID);
          expect(res.body, url).not.toContain('kakao');
        }
      }
    }
    // 대부분은 실제 데이터를 돌려줘야 의미가 있다
    expect(checked.filter((c) => c.endsWith(' 200')).length).toBeGreaterThan(20);
  });

  it('관리자 화면 응답에도 생년월일·소셜 ID는 없다', async () => {
    await app.ready();
    const u = await makeUser('관리대상염소');
    await db.user.update({
      where: { id: u.id },
      data: { birthDate: new Date(`${BIRTH}T00:00:00Z`) },
    });
    await db.authIdentity.updateMany({
      where: { userId: u.id },
      data: { providerUserId: PROVIDER_ID },
    });
    const admin = await adminToken();
    const h = { authorization: `Bearer ${admin}` };
    for (const url of ['/admin/users?q=관리', `/admin/users/${u.id}`, '/admin/dashboard']) {
      const res = await app.inject({ method: 'GET', url, headers: h });
      expect(res.statusCode, res.body).toBe(200);
      expect(res.body).not.toContain(BIRTH);
      expect(res.body).not.toContain(PROVIDER_ID);
      expect(res.body).not.toContain('"birthDate"');
    }
  });
});

describe('위치 규칙', () => {
  it('지역 보고는 지역 코드만 받고, 좌표가 섞이면 거절한다', async () => {
    const u = await makeUser('위치염소');
    const bad = await u.post('/me/region', { regionCode: '11110', lat: 37.5729, lng: 126.9794 });
    expect(bad.statusCode).toBe(400);
    const ok = await u.post('/me/region', { regionCode: '11110' });
    expect(ok.statusCode, ok.body).toBe(200);
    // 사용자 테이블에는 좌표 칼럼 자체가 없다
    const cols = await db.$queryRaw<{ column_name: string }[]>`
      SELECT column_name FROM information_schema.columns WHERE table_name = 'users'`;
    const names = cols.map((c) => c.column_name.toLowerCase());
    expect(names.length).toBeGreaterThan(5);
    expect(names.some((n) => /lat|lng|lon|coord|geo/.test(n))).toBe(false);
  });
});

describe('보안 헤더', () => {
  it('API 응답과 HTML 페이지에 보안 헤더가 붙는다', async () => {
    const api = await app.inject({ method: 'GET', url: '/health' });
    expect(api.headers['x-content-type-options']).toBe('nosniff');
    expect(api.headers['x-frame-options']).toBe('DENY');
    expect(api.headers['referrer-policy']).toBe('no-referrer');
    expect(String(api.headers['content-security-policy'])).toContain("default-src 'none'");
    expect(api.headers['x-powered-by']).toBeUndefined();

    const html = await app.inject({ method: 'GET', url: '/account/delete' });
    const csp = String(html.headers['content-security-policy']);
    expect(csp).toContain("script-src 'self'");
    expect(csp).not.toContain("script-src 'self' 'unsafe-inline'");
    expect(html.body).not.toMatch(/<script>(?!<\/script>)/); // 인라인 스크립트 없음
    expect(html.body).toContain('<script src="/account/delete.js"></script>');
    const js = await app.inject({ method: 'GET', url: '/account/delete.js' });
    expect(js.statusCode).toBe(200);
    expect(js.body).toContain('/account/delete-request');

    const err = await app.inject({ method: 'GET', url: '/nope' });
    expect(err.headers['x-content-type-options']).toBe('nosniff');
  });

  it('오류 응답에 내부 정보(스택·SQL)를 싣지 않는다', async () => {
    const u = await makeUser('오류염소');
    const res = await u.get('/letters/not-a-uuid');
    expect(res.statusCode).toBe(400);
    expect(res.body).not.toMatch(/at \w+ \(|prisma|SELECT|node_modules/i);
  });
});

describe('요청 제한 우회', () => {
  it('X-Forwarded-For 왼쪽 값을 바꿔도 같은 클라이언트로 센다(프록시 1단)', async () => {
    const { app: limited, db: db2 } = await createTestApp({ rateLimit: true });
    try {
      const statuses: number[] = [];
      for (let i = 0; i < 125; i++) {
        const r = await limited.inject({
          method: 'GET',
          url: '/health',
          remoteAddress: '10.0.0.9', // Caddy
          headers: { 'x-forwarded-for': `1.2.3.${i % 250}, 203.0.113.7` },
        });
        statuses.push(r.statusCode);
      }
      expect(statuses.filter((s) => s === 429).length).toBeGreaterThan(0);
    } finally {
      await limited.close();
      await db2.$disconnect();
    }
  });
});
