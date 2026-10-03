// M8: 탈퇴(앱·웹 요청) — SPEC 8 "보낸 편지·사진 삭제, 신고된 건은 30일 보존 후 삭제"
import { randomUUID } from 'node:crypto';
import type { FastifyInstance } from 'fastify';
import { afterAll, beforeAll, beforeEach, describe, expect, it } from 'vitest';
import { seed } from '../prisma/seed.js';
import { hashPassword, newTotpSecret, seal, totpCode } from '../src/admin/crypto.js';
import type { Db } from '../src/db.js';
import { adminSecretKey, loadEnv } from '../src/env.js';
import { markdownToHtml } from '../src/legal/markdown.js';
import { ScheduleService } from '../src/schedule/service.js';
import { createTestApp, resetUsers, testClock } from './helpers.js';
import { userKit, type U } from './users.js';

const T0 = new Date('2026-10-03T03:00:00Z');
const DAY = 86400_000;
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
  await db.deletionRequest.deleteMany({});
  await db.adminUser.deleteMany({});
});
afterAll(async () => {
  await app.close();
  await db.$disconnect();
});

async function goatRegion() {
  return (
    await db.goatScheduleStop.findFirstOrThrow({
      where: { arriveAt: { lte: T0 }, departAt: { gt: T0 }, goat: { kind: 'DELIVERY' } },
    })
  ).regionCode;
}

async function send(from: U, to: U, body = '안녕') {
  const r = await from.post('/letters', {
    mode: 'DIRECT',
    recipientId: to.id,
    body,
    stationeryId: 'cream',
    stickers: [],
    clientRequestId: randomUUID(),
  });
  expect(r.statusCode, r.body).toBe(201);
  return r.json<{ id: string; etaAt: string }>();
}

describe('앱에서 탈퇴 DELETE /me', () => {
  it('보낸 편지는 지우고 신고된 것은 숨겨 30일 보관, 받은 편지는 내 쪽에서만, 토큰 무효', async () => {
    const here = await goatRegion();
    const a = await makeUser('떠날이', here);
    const b = await makeUser('남을이', here);
    const plain = await send(a, b, '평범한 편지');
    const bad = await send(a, b, '신고될 편지');
    const fromB = await send(b, a, '남을이가 보낸 편지');
    await jump(new Date(plain.etaAt).getTime() + 3600_000, a, b);
    await a.get('/letters/inbox');
    await b.get('/letters/inbox');
    await b.post('/reports', { targetType: 'LETTER', targetId: bad.id, reason: 'ABUSE' });
    // 두루마리 글 하나
    await db.user.update({
      where: { id: a.id },
      data: { lastRegionCode: '11110', lastRegionReportedAt: clock.now() },
    });
    const paper = (await a.get('/rolling/current?level=CITY')).json().paper.id;
    await a.post(`/rolling/${paper}/entries`, { body: '안녕', stickers: [] });

    expect((await a.del('/me')).statusCode).toBe(204);
    expect((await a.get('/me')).statusCode).toBe(401);

    // 남을이: 떠날이의 편지는 받은 편지함에서 사라지고, 보낸 편지의 받는 사람은 "탈퇴한 사용자"
    expect((await b.get('/letters/inbox')).json().letters).toEqual([]);
    const sentByB = (await b.get('/letters/sent')).json().letters;
    expect(sentByB).toMatchObject([{ id: fromB.id, recipient: { nickname: '탈퇴한 사용자' } }]);
    expect(await db.letter.findUnique({ where: { id: plain.id } })).toBeNull();
    expect(await db.letter.findUnique({ where: { id: bad.id } })).toMatchObject({
      hiddenForRecipient: true,
    });
    expect(await db.rollingEntry.count({ where: { authorId: a.id } })).toBe(0);

    const row = await db.user.findUniqueOrThrow({ where: { id: a.id } });
    expect(row).toMatchObject({
      status: 'DELETED',
      nickname: null,
      birthDate: null,
      pointsBalance: 0,
    });
    expect(await db.authIdentity.count({ where: { userId: a.id } })).toBe(0);
    expect(await db.pointsLedger.count({ where: { userId: a.id } })).toBe(0);

    // 같은 카카오 계정으로 다시 오면 새 계정, 닉네임도 다시 쓸 수 있다
    const again = await app.inject({
      method: 'POST',
      url: '/auth/kakao',
      payload: { accessToken: 'kakao-ok:떠날이' },
    });
    expect(again.json().isNew).toBe(true);
    expect(again.json().me.id).not.toBe(a.id);
    const check = await app.inject({
      method: 'GET',
      url: '/nicknames/check?nick=떠날이',
      headers: { authorization: `Bearer ${again.json().accessToken}` },
    });
    expect(check.json().available).toBe(true);

    // 30일 뒤 신고 증거까지 정리
    await jump(T0.getTime() + 29 * DAY);
    expect(await app.account.purgeDeleted()).toBe(0);
    await jump(T0.getTime() + 32 * DAY);
    expect(await app.account.purgeDeleted()).toBe(1);
    expect(await db.letter.findUnique({ where: { id: bad.id } })).toBeNull();
    expect(await db.report.count({ where: { targetUserId: a.id } })).toBe(1); // 신고 기록 자체는 남음(편지 연결은 끊김)
  });
});

describe('웹 페이지', () => {
  it('약관·개인정보처리방침', async () => {
    const r = await app.inject({ method: 'GET', url: '/legal/privacy' });
    expect(r.statusCode).toBe(200);
    expect(r.headers['content-type']).toContain('text/html');
    expect(r.body).toContain('<h1>메에일 개인정보처리방침</h1>');
    expect(r.body).toContain('정확한 위치 좌표는 서버로 보내지도 저장하지도 않습니다');
    expect((await app.inject({ method: 'GET', url: '/legal/terms' })).body).toContain('제13조');
    expect((await app.inject({ method: 'GET', url: '/legal/secret' })).statusCode).toBe(400);
  });

  it('계정 삭제 안내 + 요청(앱 없이)', async () => {
    const page = await app.inject({ method: 'GET', url: '/account/delete' });
    expect(page.body).toContain('탈퇴하기');
    const ok = await app.inject({
      method: 'POST',
      url: '/account/delete-request',
      payload: { nickname: '앱지운사람', contact: 'me@example.com', message: '지워 주세요' },
    });
    expect(ok.statusCode).toBe(201);
    const bad = await app.inject({
      method: 'POST',
      url: '/account/delete-request',
      payload: { nickname: '앱지운사람', contact: 'not-an-email' },
    });
    expect(bad.statusCode).toBe(400);
    expect(await db.deletionRequest.count()).toBe(1);
  });

  it('마크다운 변환은 HTML을 그대로 넣지 않는다', () => {
    const html = markdownToHtml('# 제목\n<script>x</script> **굵게**\n- 하나\n- 둘\n\n1. 첫째');
    expect(html).toContain('&lt;script&gt;');
    expect(html).toContain('<strong>굵게</strong>');
    expect(html).toContain('<ul>\n<li>하나</li>\n<li>둘</li>\n</ul>');
    expect(html).toContain('<ol>\n<li>첫째</li>\n</ol>');
  });
});

describe('관리자: 웹 탈퇴 요청 처리', () => {
  const key = adminSecretKey(
    loadEnv({
      ...process.env,
      DATABASE_URL: 'postgres://x@localhost/x',
      JWT_SECRET: process.env.JWT_SECRET ?? 'test-secret-0123456789abcdef0123456789',
    }),
  );
  async function admin(role: 'ADMIN' | 'MODERATOR') {
    const secret = newTotpSecret();
    await db.adminUser.create({
      data: {
        username: role.toLowerCase(),
        role,
        passwordHash: await hashPassword('pw-1234567890'),
        totpSecret: seal(secret, key),
      },
    });
    const r = await app.inject({
      method: 'POST',
      url: '/admin/login',
      payload: {
        username: role.toLowerCase(),
        password: 'pw-1234567890',
        totp: totpCode(secret, clock.now().getTime()),
      },
    });
    const h = { authorization: `Bearer ${r.json().token as string}` };
    return {
      get: (url: string) => app.inject({ method: 'GET', url, headers: h }),
      post: (url: string, payload: object) =>
        app.inject({ method: 'POST', url, headers: h, payload }),
    };
  }

  it('닉네임이 맞는 계정을 찾아 보여 주고, 삭제하면 연락처도 지운다', async () => {
    const u = await makeUser('지울사람');
    await app.inject({
      method: 'POST',
      url: '/account/delete-request',
      payload: { nickname: '지울사람', contact: 'a@b.co' },
    });
    await app.inject({
      method: 'POST',
      url: '/account/delete-request',
      payload: { nickname: '없는사람' },
    });
    const mod = await admin('MODERATOR');
    const boss = await admin('ADMIN');
    const list = (await mod.get('/admin/deletion-requests')).json().requests;
    const mine = list.find((x: { nickname: string }) => x.nickname === '지울사람');
    expect(mine.match).toMatchObject({ id: u.id });
    expect(
      (await mod.post(`/admin/deletion-requests/${mine.id}/process`, { action: 'DELETE' }))
        .statusCode,
    ).toBe(403);
    expect(
      (await boss.post(`/admin/deletion-requests/${mine.id}/process`, { action: 'DELETE' })).json()
        .result,
    ).toBe('DELETED');
    expect((await db.user.findUniqueOrThrow({ where: { id: u.id } })).status).toBe('DELETED');
    expect(
      (await db.deletionRequest.findUniqueOrThrow({ where: { id: mine.id } })).contact,
    ).toBeNull();
    const other = list.find((x: { nickname: string }) => x.nickname === '없는사람');
    expect(
      (await boss.post(`/admin/deletion-requests/${other.id}/process`, { action: 'DELETE' })).json()
        .result,
    ).toBe('NOT_FOUND');
    expect(
      (await boss.post(`/admin/deletion-requests/${other.id}/process`, { action: 'DELETE' }))
        .statusCode,
    ).toBe(409);
  });
});
