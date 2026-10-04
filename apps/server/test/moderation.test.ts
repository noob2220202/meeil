// M6 완료 조건: 관리자 삭제 → 염소 먹기 연출·알림 (SPEC 9) + 신고·차단·관리자
import { randomUUID } from 'node:crypto';
import type { FastifyInstance } from 'fastify';
import sharp from 'sharp';
import { afterAll, beforeAll, beforeEach, describe, expect, it } from 'vitest';
import { seed } from '../prisma/seed.js';
import { hashPassword, newTotpSecret, seal, totpCode } from '../src/admin/crypto.js';
import type { Db } from '../src/db.js';
import { adminSecretKey, loadEnv } from '../src/env.js';
import type { MemoryPusher } from '../src/push/push.js';
import { ScheduleService } from '../src/schedule/service.js';
import { createTestApp, resetUsers, testClock } from './helpers.js';
import { userKit, type U } from './users.js';

const T0 = new Date('2026-10-03T03:00:00Z');
const DAY = 86400_000;
const clock = testClock(T0);
let app: FastifyInstance;
let db: Db;
let pusher: MemoryPusher;
const { makeUser, jump } = userKit(
  () => app,
  () => db,
  clock,
);

beforeAll(async () => {
  ({ app, db, pusher } = await createTestApp({ now: clock.now }));
  await seed(db);
  await db.goatScheduleStop.deleteMany({});
  await new ScheduleService(db).refresh(new Date(T0.getTime() - 3600_000));
});
beforeEach(async () => {
  clock.set(T0);
  pusher.sent.length = 0;
  await resetUsers(db);
  await db.adminUser.deleteMany({});
});
afterAll(async () => {
  await app.close();
  await db.$disconnect();
});

// ───────── 관리자 ─────────

const secretKey = adminSecretKey(
  loadEnv({
    ...process.env,
    DATABASE_URL: 'postgres://x@localhost/x',
    JWT_SECRET: process.env.JWT_SECRET ?? 'test-secret-0123456789abcdef0123456789',
  }),
);

interface Admin {
  token: string;
  get: (url: string) => Promise<{ statusCode: number; json: <T = any>() => T }>; // eslint-disable-line @typescript-eslint/no-explicit-any
  post: (url: string, payload?: object) => Promise<{ statusCode: number; json: <T = any>() => T }>; // eslint-disable-line @typescript-eslint/no-explicit-any
}

async function makeAdmin(
  username = 'moder',
  role: 'ADMIN' | 'MODERATOR' = 'ADMIN',
): Promise<Admin> {
  const secret = newTotpSecret();
  await db.adminUser.create({
    data: {
      username,
      role,
      passwordHash: await hashPassword('correct horse battery'),
      totpSecret: seal(secret, secretKey),
    },
  });
  const r = await app.inject({
    method: 'POST',
    url: '/admin/login',
    payload: {
      username,
      password: 'correct horse battery',
      totp: totpCode(secret, clock.now().getTime()),
    },
  });
  expect(r.statusCode, r.body).toBe(200);
  const token = r.json<{ token: string }>().token;
  const h = { authorization: `Bearer ${token}` };
  return {
    token,
    get: (url) => app.inject({ method: 'GET', url, headers: h }),
    post: (url, payload = {}) => app.inject({ method: 'POST', url, headers: h, payload }),
  };
}

async function goatRegion() {
  const stop = await db.goatScheduleStop.findFirstOrThrow({
    where: { arriveAt: { lte: T0 }, departAt: { gt: T0 }, goat: { kind: 'DELIVERY' } },
  });
  return stop.regionCode;
}

async function upload(u: U): Promise<string> {
  const img = await sharp({
    create: { width: 400, height: 300, channels: 3, background: '#ffc9d6' },
  })
    .jpeg()
    .toBuffer();
  const boundary = '----meeil';
  const r = await app.inject({
    method: 'POST',
    url: '/photos',
    headers: {
      authorization: `Bearer ${u.token}`,
      'content-type': `multipart/form-data; boundary=${boundary}`,
    },
    payload: Buffer.concat([
      Buffer.from(
        `--${boundary}\r\nContent-Disposition: form-data; name="photo"; filename="p.jpg"\r\nContent-Type: image/jpeg\r\n\r\n`,
      ),
      img,
      Buffer.from(`\r\n--${boundary}--\r\n`),
    ]),
  });
  return r.json<{ photoId: string }>().photoId;
}

async function send(from: U, to: U, extra: object = {}) {
  const r = await from.post('/letters', {
    mode: 'DIRECT',
    recipientId: to.id,
    body: '이상한 편지',
    stationeryId: 'cream',
    stickers: [],
    clientRequestId: randomUUID(),
    ...extra,
  });
  expect(r.statusCode, r.body).toBe(201);
  return r.json<{ id: string; etaAt: string }>();
}

describe('관리자 로그인 (ID/PW + TOTP)', () => {
  it('비밀번호·코드가 틀리면 거절, 사용자 토큰과 서로 바꿔 쓸 수 없다', async () => {
    const secret = newTotpSecret();
    await db.adminUser.create({
      data: {
        username: 'kim',
        passwordHash: await hashPassword('pw-123456789'),
        totpSecret: seal(secret, secretKey),
      },
    });
    const login = (password: string, totp: string) =>
      app.inject({
        method: 'POST',
        url: '/admin/login',
        payload: { username: 'kim', password, totp },
      });
    const now = clock.now().getTime();
    expect((await login('wrong', totpCode(secret, now))).statusCode).toBe(401);
    expect((await login('pw-123456789', totpCode(secret, now + 5 * 60_000))).statusCode).toBe(401);
    const ok = await login('pw-123456789', totpCode(secret, now - 30_000)); // 한 칸 전은 허용
    expect(ok.statusCode).toBe(200);
    const adminToken = ok.json().token as string;

    const u = await makeUser('일반인');
    const asUser = await app.inject({
      method: 'GET',
      url: '/admin/me',
      headers: { authorization: `Bearer ${u.token}` },
    });
    expect(asUser.statusCode).toBe(401);
    const asAdmin = await app.inject({
      method: 'GET',
      url: '/me',
      headers: { authorization: `Bearer ${adminToken}` },
    });
    expect(asAdmin.statusCode).toBe(401);
    // 시크릿은 DB에 평문으로 있지 않다
    const row = await db.adminUser.findUniqueOrThrow({ where: { username: 'kim' } });
    expect(row.totpSecret).not.toContain(secret);
    expect(await db.auditLog.count({ where: { action: 'LOGIN' } })).toBe(1);
  });
});

describe('신고·차단 (SPEC 9.1)', () => {
  it('받은 편지 신고(중복은 한 번), 남의 편지는 신고 못 함', async () => {
    const here = await goatRegion();
    const a = await makeUser('보낸이', here);
    const b = await makeUser('받은이', here);
    const c = await makeUser('구경꾼', here);
    const l = await send(a, b);
    await jump(new Date(l.etaAt).getTime() + 60_000, a, b, c);
    await b.get('/letters/inbox');

    const r1 = await b.post('/reports', {
      targetType: 'LETTER',
      targetId: l.id,
      reason: 'ABUSE',
      detail: '욕설',
    });
    expect(r1.statusCode).toBe(201);
    const r2 = await b.post('/reports', { targetType: 'LETTER', targetId: l.id, reason: 'SPAM' });
    expect(r2.json()).toMatchObject({ id: r1.json().id, duplicate: true });
    expect(
      (await c.post('/reports', { targetType: 'LETTER', targetId: l.id, reason: 'SPAM' }))
        .statusCode,
    ).toBe(404);
    expect(
      (await b.post('/reports', { targetType: 'USER', targetId: b.id, reason: 'SPAM' })).statusCode,
    ).toBe(400);
    expect(
      (await b.post('/reports', { targetType: 'USER', targetId: a.id, reason: 'NOPE' })).statusCode,
    ).toBe(400);
    const rep = await db.report.findUniqueOrThrow({ where: { id: r1.json().id } });
    expect(rep).toMatchObject({ targetUserId: a.id, letterId: l.id, status: 'OPEN' });
    expect((await b.get('/reports/reasons')).json().reasons).toContainEqual({
      code: 'ABUSE',
      label: '욕설·괴롭힘',
    });
  });

  it('차단하면 받은 편지·검색·두루마리에서 사라지고, 해제하면 돌아온다', async () => {
    const here = await goatRegion();
    const a = await makeUser('귀찮은이', here);
    const b = await makeUser('차단왕', here);
    const l = await send(a, b);
    await jump(new Date(l.etaAt).getTime() + 60_000, a, b);
    expect((await b.get('/letters/inbox')).json().letters).toHaveLength(1);

    expect((await b.post('/blocks', { userId: a.id })).statusCode).toBe(201);
    expect((await b.post('/blocks', { userId: a.id })).statusCode).toBe(201); // 다시 눌러도 그대로
    expect((await b.get('/blocks')).json().blocks).toMatchObject([
      { userId: a.id, nickname: '귀찮은이' },
    ]);
    expect((await b.get('/letters/inbox')).json().letters).toHaveLength(0);
    expect((await b.get('/users/search?nick=귀찮')).json().users).toEqual([]);
    expect((await a.get('/users/search?nick=차단')).json().users).toEqual([]);

    // 두루마리: 같은 시 장에서 차단한 사람 글 숨김
    await db.user.updateMany({
      where: { id: { in: [a.id, b.id] } },
      data: { lastRegionCode: '11110', lastRegionReportedAt: clock.now() },
    });
    const paper = (await a.get('/rolling/current?level=CITY')).json().paper.id;
    await a.post(`/rolling/${paper}/entries`, { body: '안녕', stickers: [] });
    expect((await b.get(`/rolling/${paper}`)).json().entries).toEqual([]);

    expect((await b.del(`/blocks/${a.id}`)).statusCode).toBe(200);
    expect((await b.get('/letters/inbox')).json().letters).toHaveLength(1);
    expect((await b.get(`/rolling/${paper}`)).json().entries).toHaveLength(1);
    expect((await b.post('/blocks', { userId: b.id })).statusCode).toBe(400);
  });

  it('랜덤 받기 끄기·알림 끄기', async () => {
    const a = await makeUser('설정이');
    const r = await a.put('/me/settings', { randomReceive: false });
    expect(r.json()).toEqual({ randomReceive: false, notifyEnabled: true });
    expect((await a.get('/me')).json().randomReceive).toBe(false);
    expect((await a.put('/me/settings', {})).statusCode).toBe(400);
  });
});

describe('염소가 편지를 먹어버린다 (SPEC 9.3)', () => {
  it('배달 전: 받는 사람에게 가지 않고, 보낸 사람에게 알림, 신고는 처리됨', async () => {
    const here = await goatRegion();
    const a = await makeUser('나쁜편지', here);
    const b = await makeUser('받을사람', here);
    const admin = await makeAdmin();
    const l = await send(a, b);
    // 받는 사람은 아직 못 받았으니 신고는 보낸 사람 쪽에서 만들어 둔다(관리자 큐 확인용)
    await db.report.create({
      data: { reporterId: b.id, targetType: 'USER', targetUserId: a.id, reason: 'ABUSE' },
    });

    const r = await admin.post(`/admin/letters/${l.id}/eat`, { reason: '욕설' });
    expect(r.json()).toMatchObject({ eaten: true, wasDelivered: false });
    expect((await admin.post(`/admin/letters/${l.id}/eat`)).json().eaten).toBe(false); // 한 번만

    const push = pusher.sent.find((p) => p.userId === a.id);
    expect(push?.msg.title).toBe('염소가 편지를 먹어버렸어요');
    expect(push?.msg.body).toMatch(/받을사람님에게 가던 편지를 먹어버렸어요\. \(부적절한 내용\)$/);
    expect(push?.msg.data).toEqual({ type: 'letter-eaten', letterId: l.id });

    await jump(new Date(l.etaAt).getTime() + 3600_000, a, b);
    expect((await b.get('/letters/inbox')).json().letters).toEqual([]);
    expect((await b.get(`/letters/${l.id}`)).statusCode).toBe(404);
    const mine = (await a.get(`/letters/${l.id}`)).json();
    expect(mine).toMatchObject({ status: 'EATEN', body: null, stickers: [] });
    expect(mine.eatenAt).toBeTruthy();
    expect(await db.auditLog.count({ where: { action: 'LETTER_EAT', targetId: l.id } })).toBe(1);
  });

  it('이미 도착: 보관함에서 "먹힌 편지"로 바뀌고 신고가 처리된다', async () => {
    const here = await goatRegion();
    const a = await makeUser('늦게걸림', here);
    const b = await makeUser('신고자', here);
    const l = await send(a, b);
    await jump(new Date(l.etaAt).getTime() + 60_000, a, b);
    const admin = await makeAdmin(); // 관리자 토큰은 8시간이라 시계를 옮긴 뒤 로그인
    await b.get('/letters/inbox');
    await b.post('/reports', { targetType: 'LETTER', targetId: l.id, reason: 'SEXUAL' });

    const queue = (await admin.get('/admin/reports')).json().reports;
    expect(queue).toHaveLength(1);
    expect(queue[0]).toMatchObject({
      reasonLabel: '성적인 내용',
      letter: { id: l.id, body: '이상한 편지' },
      sameTargetOpen: 1,
    });

    expect((await admin.post(`/admin/letters/${l.id}/eat`)).json()).toMatchObject({
      eaten: true,
      wasDelivered: true,
    });
    const inbox = (await b.get('/letters/inbox')).json().letters;
    expect(inbox).toMatchObject([{ id: l.id, status: 'EATEN', body: null }]);
    expect((await admin.get('/admin/reports')).json().reports).toEqual([]);
    const done = (await admin.get('/admin/reports?status=RESOLVED')).json().reports;
    expect(done[0]).toMatchObject({ status: 'RESOLVED', resolvedBy: 'moder' });
  });

  it('두루마리 글 먹기', async () => {
    const a = await makeUser('두루글');
    const admin = await makeAdmin();
    const paper = (await a.get('/rolling/current?level=CITY')).json().paper.id;
    const e = (
      await a.post(`/rolling/${paper}/entries`, {
        body: '나쁜 말',
        stickers: [{ id: 'heart', x: 0, y: 0 }],
      })
    ).json();
    expect((await admin.post(`/admin/rolling-entries/${e.id}/eat`)).json().eaten).toBe(true);
    const view = (await a.get(`/rolling/${paper}`)).json();
    expect(view.entries[0]).toMatchObject({ id: e.id, status: 'EATEN', body: null, stickers: [] });
    expect(
      pusher.sent.some(
        (p) => p.userId === a.id && p.msg.title === '염소가 두루마리 글을 먹어버렸어요',
      ),
    ).toBe(true);
  });

  it('30일 지나면 먹힌 원본(본문·사진)을 지운다', async () => {
    const here = await goatRegion();
    const a = await makeUser('증거', here);
    const b = await makeUser('증거받음', here);
    const admin = await makeAdmin();
    const photoId = await upload(a);
    const l = await send(a, b, { photoId });
    await admin.post(`/admin/letters/${l.id}/eat`);
    await jump(T0.getTime() + 29 * DAY);
    expect(await app.eat.purgeEvidence()).toBe(0);
    await jump(T0.getTime() + 31 * DAY);
    expect(await app.eat.purgeEvidence()).toBe(1);
    const row = await db.letter.findUniqueOrThrow({
      where: { id: l.id },
      include: { photo: true },
    });
    expect(row.body).toBe('');
    expect(row.photo).toBeNull();
  });
});

describe('사진 검수 피드', () => {
  it('최신순, 확인 완료하면 미확인 목록에서 빠진다', async () => {
    const here = await goatRegion();
    const a = await makeUser('찍사', here);
    const b = await makeUser('보는이', here);
    const admin = await makeAdmin('photo', 'MODERATOR');
    const l1 = await send(a, b, { photoId: await upload(a), body: '첫 사진' });
    clock.set(new Date(T0.getTime() + 60_000));
    const l2 = await send(a, b, { photoId: await upload(a), body: '둘째 사진' });
    const feed = (await admin.get('/admin/photos')).json().photos;
    expect(feed.map((p: { letter: { id: string } }) => p.letter.id)).toEqual([l2.id, l1.id]);
    expect(feed[0]).toMatchObject({
      reviewedAt: null,
      letter: { body: '둘째 사진', sender: { nickname: '찍사' } },
    });
    expect(feed[0].url).toMatch(/^http:\/\/media\.test\//);

    await admin.post(`/admin/photos/${feed[0].id}/review`);
    const after = (await admin.get('/admin/photos')).json().photos;
    expect(after.map((p: { letter: { id: string } }) => p.letter.id)).toEqual([l1.id]);
    const all = (await admin.get('/admin/photos?filter=all')).json().photos;
    expect(all[0]).toMatchObject({ reviewedBy: 'photo' });
    // 먹으면 검수도 끝난 것으로
    await admin.post(`/admin/letters/${l1.id}/eat`);
    expect((await admin.get('/admin/photos')).json().photos).toEqual([]);
  });
});

describe('제재: 경고 → 7일 정지 → 영구 정지', () => {
  it('정지 중엔 편지·두루마리 불가, 영구 정지는 최고 관리자만, 해제', async () => {
    const here = await goatRegion();
    const a = await makeUser('말썽꾼', here);
    const b = await makeUser('피해자', here);
    const mod = await makeAdmin('mod', 'MODERATOR');
    const boss = await makeAdmin('boss', 'ADMIN');

    expect(
      (await mod.post(`/admin/users/${a.id}/sanctions`, { type: 'WARNING', reason: '욕설' }))
        .statusCode,
    ).toBe(200);
    expect(pusher.sent.at(-1)).toMatchObject({ userId: a.id, msg: { title: '운영 정책 안내' } });

    const s = (
      await mod.post(`/admin/users/${a.id}/sanctions`, { type: 'SUSPEND_7D', reason: '반복' })
    ).json();
    expect(s.status).toBe('SUSPENDED');
    expect(new Date(s.suspendedUntil).getTime()).toBe(T0.getTime() + 7 * DAY);
    const r = await a.post('/letters', {
      mode: 'DIRECT',
      recipientId: b.id,
      body: '안녕',
      stationeryId: 'cream',
      stickers: [],
      clientRequestId: randomUUID(),
    });
    expect(r.json().error.code).toBe('SUSPENDED');

    expect(
      (await mod.post(`/admin/users/${a.id}/sanctions`, { type: 'BAN', reason: '악성' }))
        .statusCode,
    ).toBe(403);
    expect(
      (await boss.post(`/admin/users/${a.id}/sanctions`, { type: 'BAN', reason: '악성' })).json()
        .status,
    ).toBe('BANNED');
    expect((await a.get('/me')).json().error.code).toBe('BANNED');
    expect(await db.refreshToken.count({ where: { userId: a.id, revokedAt: null } })).toBe(0);

    const detail = (await mod.get(`/admin/users/${a.id}`)).json();
    expect(detail.sanctions.map((x: { type: string }) => x.type)).toEqual([
      'BAN',
      'SUSPEND_7D',
      'WARNING',
    ]);
    expect(JSON.stringify(detail)).not.toContain('2000-01-01'); // 생년월일 비노출
    expect(detail.ageVerified).toBe(true);

    await boss.post(`/admin/users/${a.id}/sanctions`, { type: 'LIFT', reason: '소명' });
    expect((await db.user.findUniqueOrThrow({ where: { id: a.id } })).status).toBe('ACTIVE');
    const found = (await mod.get('/admin/users?q=말썽')).json().users;
    expect(found).toMatchObject([{ id: a.id, nickname: '말썽꾼' }]);
  });
});

describe('공지·주제·공식 글·특급·대시보드·감사', () => {
  it('공지 + 푸시(알림 켠 사람만), 앱 공지 목록', async () => {
    const a = await makeUser('알림켬');
    const b = await makeUser('알림끔');
    await db.fcmToken.createMany({
      data: [
        { token: 'a'.repeat(40), userId: a.id },
        { token: 'b'.repeat(40), userId: b.id },
      ],
    });
    await b.put('/me/settings', { notifyEnabled: false });
    const mod = await makeAdmin('mod2', 'MODERATOR');
    const boss = await makeAdmin('boss2', 'ADMIN');
    const body = {
      title: '염소 우체국 개국!',
      body: '메에일을 찾아 줘서 고마워요.',
      pinned: true,
      push: true,
    };
    expect((await mod.post('/admin/notices', body)).statusCode).toBe(403);
    expect((await boss.post('/admin/notices', body)).json().pushed).toBe(1);
    expect(pusher.sent.map((p) => p.userId)).toEqual([a.id]);
    expect((await a.get('/notices')).json().notices).toMatchObject([
      { title: '염소 우체국 개국!', pinned: true },
    ]);
  });

  it('롤링 주제: 레벨 전체(*) → 지역별 덮어쓰기, 다음 장 예약', async () => {
    const a = await makeUser('주제읽기', '11110');
    const c = await makeUser('부산주제', '26110');
    const admin = await makeAdmin();
    await admin.post('/admin/rolling/topics', {
      level: 'CITY',
      scopeCode: '*',
      topic: '오늘의 날씨',
    });
    await admin.post('/admin/rolling/topics', {
      level: 'CITY',
      scopeCode: '26110',
      topic: '바다 이야기',
    });
    await admin.post('/admin/rolling/topics', {
      level: 'CITY',
      scopeCode: '*',
      when: 'next',
      topic: '내일의 주제',
    });
    expect((await a.get('/rolling/current?level=CITY')).json().paper.topic).toBe('오늘의 날씨');
    expect((await c.get('/rolling/current?level=CITY')).json().paper.topic).toBe('바다 이야기');
    await jump(T0.getTime() + DAY, a);
    await db.user.update({ where: { id: a.id }, data: { lastRegionReportedAt: clock.now() } });
    expect((await a.get('/rolling/current?level=CITY')).json().paper.topic).toBe('내일의 주제');
  });

  it('공식 계정 환영 글, 특급 배달, 대시보드, 감사 로그', async () => {
    const here = await goatRegion();
    const a = await makeUser('대시보드', here);
    const b = await makeUser('특급받음', here);
    const admin = await makeAdmin();
    const e = await admin.post('/admin/rolling/official-entry', {
      level: 'NATION',
      scopeCode: 'KR',
      body: '어서 와요!',
    });
    expect(e.statusCode).toBe(201);
    const nation = (await a.get('/rolling/current?level=NATION')).json();
    expect(nation.entries).toMatchObject([
      { body: '어서 와요!', author: { nickname: '메에일 우체국' } },
    ]);

    const l = await send(a, b);
    const x = (await admin.post(`/admin/letters/${l.id}/express`)).json();
    expect(new Date(x.etaAt).getTime()).toBe(T0.getTime() + 60_000);
    await jump(T0.getTime() + 2 * 60_000, b);
    expect((await b.get('/letters/inbox')).json().letters).toHaveLength(1);

    const d = (await admin.get('/admin/dashboard')).json();
    expect(d).toMatchObject({ users: 2, lettersToday: 1, openReports: 0 });
    expect(d.days).toHaveLength(7);
    const logs = (await admin.get('/admin/audit'))
      .json()
      .logs.map((l: { action: string }) => l.action);
    expect(logs).toEqual(
      expect.arrayContaining(['LOGIN', 'ROLLING_OFFICIAL_ENTRY', 'LETTER_EXPRESS']),
    );
  });
});
