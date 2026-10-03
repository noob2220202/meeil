// M3 완료 조건: 두 계정 사이 편지 왕복 + 규칙·오류·사진·보관함
import { randomUUID } from 'node:crypto';
import type { FastifyInstance } from 'fastify';
import sharp from 'sharp';
import { afterAll, beforeAll, beforeEach, describe, expect, it } from 'vitest';
import { seed } from '../prisma/seed.js';
import type { Db } from '../src/db.js';
import type { LetterDto } from '../src/letters/service.js';
import { notifyGoatArrivals } from '../src/push/goat-arrival.js';
import type { MemoryPusher } from '../src/push/push.js';
import { ScheduleService } from '../src/schedule/service.js';
import { createTestApp, resetUsers, testClock } from './helpers.js';

const T0 = new Date('2026-10-03T03:00:00Z'); // KST 12:00
const clock = testClock(T0);
let app: FastifyInstance;
let db: Db;
let pusher: MemoryPusher;

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
});
afterAll(async () => {
  await app.close();
  await db.$disconnect();
});

/** [at] 시각에 배달 염소가 머무는 시 / 아무 염소도 없는 시 */
async function regionsAt(at: Date) {
  const stops = await db.goatScheduleStop.findMany({
    where: { arriveAt: { lte: at }, departAt: { gt: at }, goat: { kind: 'DELIVERY' } },
  });
  const busy = new Set(stops.map((s) => s.regionCode));
  const all = (await db.region.findMany({ select: { code: true } })).map((r) => r.code);
  return { withGoat: [...busy].sort(), withoutGoat: all.filter((c) => !busy.has(c)) };
}

interface InjectRes {
  statusCode: number;
  body: string;
  rawPayload: Buffer;
  headers: Record<string, unknown>;
  json: <T = unknown>() => T;
}

interface TestUser {
  id: string;
  nickname: string;
  token: string;
  get: (url: string) => Promise<InjectRes>;
  post: (url: string, payload?: object) => Promise<InjectRes>;
  del: (url: string) => Promise<InjectRes>;
}

async function loginToken(nickname: string): Promise<string> {
  const login = await app.inject({
    method: 'POST',
    url: '/auth/kakao',
    payload: { accessToken: `kakao-ok:${nickname}` },
  });
  return login.json<{ accessToken: string }>().accessToken;
}

/** 가입을 마친 사용자를 만들고 [region]에 있다고 보고한다 */
async function makeUser(nickname: string, region: string): Promise<TestUser> {
  const u: TestUser = {
    id: '',
    nickname,
    token: await loginToken(nickname),
    get: (url) =>
      app.inject({ method: 'GET', url, headers: { authorization: `Bearer ${u.token}` } }),
    post: (url, payload = {}) =>
      app.inject({ method: 'POST', url, headers: { authorization: `Bearer ${u.token}` }, payload }),
    del: (url) =>
      app.inject({ method: 'DELETE', url, headers: { authorization: `Bearer ${u.token}` } }),
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
  await placeAt(u.id, region);
  return u;
}

/** 시계를 옮기고(access 토큰 1시간 만료) 다시 로그인한다 */
async function jump(to: Date | number, ...users: TestUser[]) {
  clock.set(new Date(to));
  for (const u of users) u.token = await loginToken(u.nickname);
}

/** 위치 보고 대신 DB에 직접(속도 검사 없이 장면 전환) */
async function placeAt(userId: string, region: string) {
  await db.user.update({
    where: { id: userId },
    data: { lastRegionCode: region, lastRegionReportedAt: clock.now(), lastActiveAt: clock.now() },
  });
}

const letter = (extra: object = {}) => ({
  mode: 'DIRECT',
  body: '안녕! 염소가 전해 주는 첫 편지야.',
  stationeryId: 'cream',
  stickers: [{ id: 'heart', x: 0.8, y: 0.1 }],
  clientRequestId: randomUUID(),
  ...extra,
});

async function points(userId: string) {
  return (await db.user.findUniqueOrThrow({ where: { id: userId } })).pointsBalance;
}

describe('두 계정 편지 왕복', () => {
  it('A가 맡긴 편지가 염소 도착 시각에 B에게 가고, B의 답장이 A에게 돌아온다', async () => {
    const { withGoat } = await regionsAt(T0);
    const a = await makeUser('보내는염소', withGoat[0]!);
    const b = await makeUser('받는염소', withGoat[1] ?? withGoat[0]!);

    // 1) A가 맡긴다
    const hand = await a.post('/letters', letter({ recipientId: b.id }));
    expect(hand.statusCode).toBe(201);
    const sent = hand.json<LetterDto>();
    expect(sent.status).toBe('IN_TRANSIT');
    expect(sent.goat).not.toBeNull();
    expect(sent.pickupGoatId).toBeTruthy();
    const eta = Date.parse(sent.etaAt!);
    expect(eta).toBeGreaterThanOrEqual(T0.getTime() + 3600_000);
    expect(eta).toBeLessThanOrEqual(T0.getTime() + 72 * 3600_000);
    expect(await points(a.id)).toBe(4); // 가입 5P - 1P

    // 도착 전: B 받은 편지함은 비어 있고, A 보낸 편지함엔 이동 중
    expect((await b.get('/letters/inbox')).json<{ letters: unknown[] }>().letters).toHaveLength(0);
    const aSent = (await a.get('/letters/sent')).json<{ letters: LetterDto[] }>().letters;
    expect(aSent.map((l) => l.status)).toEqual(['IN_TRANSIT']);

    // 2) 도착 시각이 지나면 배달 + 푸시
    await jump(eta + 1000, a, b);
    const inbox = (await b.get('/letters/inbox')).json<{ letters: LetterDto[] }>().letters;
    expect(inbox).toHaveLength(1);
    expect(inbox[0]).toMatchObject({
      status: 'DELIVERED',
      body: '안녕! 염소가 전해 주는 첫 편지야.',
      sender: { nickname: '보내는염소' },
      canReply: true,
    });
    expect(pusher.sent).toEqual([
      expect.objectContaining({
        userId: b.id,
        msg: expect.objectContaining({ title: '편지가 도착했어요' }),
      }),
    ]);
    expect((await b.get('/letters/unread-count')).json()).toEqual({ count: 0 + 1 });

    // 3) B가 읽는다
    const read = await b.post(`/letters/${inbox[0]!.id}/read`);
    expect(read.json<LetterDto>().status).toBe('READ');
    expect((await b.get('/letters/unread-count')).json()).toEqual({ count: 0 });

    // 4) B가 답장(지금 염소가 있는 시로 B를 옮긴다)
    const now = clock.now();
    const { withGoat: busyNow } = await regionsAt(now);
    await placeAt(b.id, busyNow[0]!);
    const replyRes = await b.post(
      '/letters',
      letter({ mode: 'REPLY', replyToId: inbox[0]!.id, body: '답장 고마워!' }),
    );
    expect(replyRes.statusCode).toBe(201);
    const reply = replyRes.json<LetterDto>();
    expect(reply.recipient?.nickname).toBe('보내는염소');
    expect(reply.replyToId).toBe(inbox[0]!.id);

    // 5) 답장이 A에게 도착
    await jump(Date.parse(reply.etaAt!) + 1000, a, b);
    const aInbox = (await a.get('/letters/inbox')).json<{ letters: LetterDto[] }>().letters;
    expect(aInbox.map((l) => l.body)).toEqual(['답장 고마워!']);
  });
});

describe('맡기기 규칙', () => {
  it('내 시에 배달 염소가 없으면 맡길 수 없다', async () => {
    const { withoutGoat } = await regionsAt(T0);
    const a = await makeUser('염소없는곳', withoutGoat[0]!);
    const b = await makeUser('받는사람', withoutGoat[1]!);
    const res = await a.post('/letters', letter({ recipientId: b.id }));
    expect(res.statusCode).toBe(409);
    expect(res.json()).toMatchObject({ error: { code: 'NO_GOAT_HERE' } });
    expect(await points(a.id)).toBe(5);
  });

  it('위치 보고가 30분보다 오래되면 맡길 수 없다', async () => {
    const { withGoat } = await regionsAt(T0);
    const a = await makeUser('오래된위치', withGoat[0]!);
    const b = await makeUser('받는사람', withGoat[0]!);
    await db.user.update({
      where: { id: a.id },
      data: { lastRegionReportedAt: new Date(T0.getTime() - 31 * 60_000) },
    });
    const res = await a.post('/letters', letter({ recipientId: b.id }));
    expect(res.json()).toMatchObject({ error: { code: 'REGION_UNKNOWN' } });
  });

  it('포인트가 없으면 거절되고 편지도 남지 않는다', async () => {
    const { withGoat } = await regionsAt(T0);
    const a = await makeUser('빈지갑', withGoat[0]!);
    const b = await makeUser('받는사람', withGoat[0]!);
    await db.user.update({ where: { id: a.id }, data: { pointsBalance: 0 } });
    const res = await a.post('/letters', letter({ recipientId: b.id }));
    expect(res.statusCode).toBe(409);
    expect(res.json()).toMatchObject({ error: { code: 'INSUFFICIENT_POINTS' } });
    expect(await db.letter.count()).toBe(0);
  });

  it('같은 요청을 두 번 보내도 한 통만, 포인트도 한 번만', async () => {
    const { withGoat } = await regionsAt(T0);
    const a = await makeUser('두번누름', withGoat[0]!);
    const b = await makeUser('받는사람', withGoat[0]!);
    const body = letter({ recipientId: b.id });
    const r1 = await a.post('/letters', body);
    const r2 = await a.post('/letters', body);
    expect(r2.json<LetterDto>().id).toBe(r1.json<LetterDto>().id);
    expect(await db.letter.count()).toBe(1);
    expect(await points(a.id)).toBe(4);
  });

  it('하루 20통까지(KST 하루)', async () => {
    const { withGoat } = await regionsAt(T0);
    const a = await makeUser('부지런', withGoat[0]!);
    const b = await makeUser('받는사람', withGoat[0]!);
    await db.user.update({ where: { id: a.id }, data: { pointsBalance: 100 } });
    await db.letter.createMany({
      data: Array.from({ length: 20 }, () => ({
        mode: 'DIRECT' as const,
        senderId: a.id,
        recipientId: b.id,
        originRegionCode: withGoat[0]!,
        destRegionCode: withGoat[0]!,
        body: '.',
        stationeryId: 'cream',
        handedAt: new Date(T0.getTime() - 3600_000),
      })),
    });
    const res = await a.post('/letters', letter({ recipientId: b.id }));
    expect(res.statusCode).toBe(429);
    expect(res.json()).toMatchObject({ error: { code: 'DAILY_LIMIT' } });
  });

  it('잠긴 편지지·200자 초과·스티커 4개·모르는 스티커·자기 자신은 거절', async () => {
    const { withGoat } = await regionsAt(T0);
    const a = await makeUser('규칙확인', withGoat[0]!);
    const b = await makeUser('받는사람', withGoat[0]!);
    const cases: [object, string][] = [
      [{ recipientId: b.id, stationeryId: 'lined' }, 'STATIONERY_LOCKED'],
      [{ recipientId: b.id, body: '가'.repeat(201) }, 'VALIDATION'],
      [{ recipientId: b.id, body: '   ' }, 'VALIDATION'],
      [
        {
          recipientId: b.id,
          stickers: ['heart', 'star', 'sun', 'moon'].map((id) => ({ id, x: 0.5, y: 0.5 })),
        },
        'VALIDATION',
      ],
      [{ recipientId: b.id, stickers: [{ id: 'skull', x: 0, y: 0 }] }, 'VALIDATION'],
      [{ recipientId: a.id }, 'SELF_LETTER'],
      [{ mode: 'DIRECT' }, 'VALIDATION'],
    ];
    for (const [extra, code] of cases) {
      const res = await a.post('/letters', letter(extra));
      expect(res.json(), JSON.stringify(extra).slice(0, 60)).toMatchObject({ error: { code } });
    }
    expect(await points(a.id)).toBe(5);
  });

  it('200자는 한글 기준으로 센다(이모지 포함)', async () => {
    const { withGoat } = await regionsAt(T0);
    const a = await makeUser('딱이백', withGoat[0]!);
    const b = await makeUser('받는사람', withGoat[0]!);
    const res = await a.post(
      '/letters',
      letter({ recipientId: b.id, body: '염'.repeat(198) + '🐐!' }),
    );
    expect(res.statusCode).toBe(201);
  });
});

describe('랜덤 편지', () => {
  it('범위 안에 받을 사람이 없으면 넓히라고 안내한다', async () => {
    const { withGoat } = await regionsAt(T0);
    const a = await makeUser('랜덤발신', withGoat[0]!);
    const res = await a.post('/letters', letter({ mode: 'RANDOM', randomScope: 'CITY' }));
    expect(res.statusCode).toBe(409);
    expect(res.json()).toMatchObject({ error: { code: 'NO_RANDOM_RECIPIENT' } });
    expect(res.json<{ error: { message: string } }>().error.message).toContain('넓혀');
  });

  it('랜덤 수신을 끈 사람·차단 관계는 제외, 받는 사람은 도착 전까지 발신자에게 감춘다', async () => {
    const { withGoat } = await regionsAt(T0);
    const region = withGoat[0]!;
    const a = await makeUser('랜덤보냄', region);
    const off = await makeUser('수신끔', region);
    const blocked = await makeUser('차단함', region);
    const ok = await makeUser('랜덤받음', region);
    await db.user.update({ where: { id: off.id }, data: { randomReceive: false } });
    await db.block.create({ data: { blockerId: blocked.id, blockedId: a.id } });

    for (let i = 0; i < 5; i++) {
      const res = await a.post('/letters', letter({ mode: 'RANDOM', randomScope: 'CITY' }));
      expect(res.statusCode).toBe(201);
      const l = res.json<LetterDto>();
      expect(l.recipient).toBeNull();
      const row = await db.letter.findUniqueOrThrow({ where: { id: l.id } });
      expect(row.recipientId).toBe(ok.id);
    }
  });

  it('랜덤 편지 사진은 받는 쪽에서 블러', async () => {
    const { withGoat } = await regionsAt(T0);
    const a = await makeUser('사진랜덤', withGoat[0]!);
    const b = await makeUser('사진받음', withGoat[0]!);
    const photoId = await upload(a, await jpeg(800, 600));
    const sent = (
      await a.post('/letters', letter({ mode: 'RANDOM', randomScope: 'CITY', photoId }))
    ).json<LetterDto>();
    expect(sent.photo?.blurred).toBe(false);
    await jump(Date.parse(sent.etaAt!) + 1000, a, b);
    const got = (await b.get('/letters/inbox')).json<{ letters: LetterDto[] }>().letters[0]!;
    expect(got.photo?.blurred).toBe(true);
    expect(got.recipient?.nickname).toBe('사진받음');
  });
});

describe('차단', () => {
  it('나를 차단한 사람에게 보낸 지정 편지는 도착하지만 그 사람 보관함에선 숨겨지고 알림도 없다', async () => {
    const { withGoat } = await regionsAt(T0);
    const a = await makeUser('차단당함', withGoat[0]!);
    const b = await makeUser('차단한사람', withGoat[0]!);
    await db.block.create({ data: { blockerId: b.id, blockedId: a.id } });
    const sent = (await a.post('/letters', letter({ recipientId: b.id }))).json<LetterDto>();
    await jump(Date.parse(sent.etaAt!) + 1000, a, b);
    expect((await b.get('/letters/inbox')).json<{ letters: unknown[] }>().letters).toHaveLength(0);
    expect((await b.get(`/letters/${sent.id}`)).statusCode).toBe(404);
    expect(pusher.sent).toHaveLength(0);
    // 보낸 사람 쪽은 정상적으로 도착으로 보인다
    expect((await a.get(`/letters/${sent.id}`)).json<LetterDto>().status).toBe('DELIVERED');
  });
});

describe('보관함·휴지통', () => {
  it('휴지통으로 → 복구 → 영구 삭제는 내 쪽만', async () => {
    const { withGoat } = await regionsAt(T0);
    const a = await makeUser('휴지통A', withGoat[0]!);
    const b = await makeUser('휴지통B', withGoat[0]!);
    const sent = (await a.post('/letters', letter({ recipientId: b.id }))).json<LetterDto>();
    await jump(Date.parse(sent.etaAt!) + 1000, a, b);

    await b.post(`/letters/${sent.id}/trash`);
    expect((await b.get('/letters/inbox')).json<{ letters: unknown[] }>().letters).toHaveLength(0);
    expect((await b.get('/letters/trash')).json<{ letters: LetterDto[] }>().letters[0]!.id).toBe(
      sent.id,
    );

    await b.post(`/letters/${sent.id}/restore`);
    expect((await b.get('/letters/inbox')).json<{ letters: unknown[] }>().letters).toHaveLength(1);

    // 휴지통에 없는 편지는 영구 삭제 불가
    expect((await b.del(`/letters/${sent.id}`)).statusCode).toBe(409);
    await b.post(`/letters/${sent.id}/trash`);
    expect((await b.del(`/letters/${sent.id}`)).statusCode).toBe(204);
    expect((await b.get('/letters/trash')).json<{ letters: unknown[] }>().letters).toHaveLength(0);
    expect((await b.get(`/letters/${sent.id}`)).statusCode).toBe(404);
    // 상대 복사본은 유지
    expect((await a.get('/letters/sent')).json<{ letters: unknown[] }>().letters).toHaveLength(1);
  });

  it('휴지통 30일이 지나면 영구 삭제, 양쪽 다 지우면 편지 자체가 사라진다', async () => {
    const { withGoat } = await regionsAt(T0);
    const a = await makeUser('삼십일A', withGoat[0]!);
    const b = await makeUser('삼십일B', withGoat[0]!);
    const sent = (await a.post('/letters', letter({ recipientId: b.id }))).json<LetterDto>();
    await jump(Date.parse(sent.etaAt!) + 1000, a, b);
    await a.post(`/letters/${sent.id}/trash`);
    await b.post(`/letters/${sent.id}/trash`);
    await jump(clock.now().getTime() + 31 * 24 * 3600_000);
    await app.letters.purgeExpiredTrash();
    expect(await db.letter.count({ where: { id: sent.id } })).toBe(0);
  });

  it('남의 편지는 볼 수 없다', async () => {
    const { withGoat } = await regionsAt(T0);
    const a = await makeUser('주인A', withGoat[0]!);
    const b = await makeUser('주인B', withGoat[0]!);
    const c = await makeUser('구경꾼', withGoat[0]!);
    const sent = (await a.post('/letters', letter({ recipientId: b.id }))).json<LetterDto>();
    expect((await c.get(`/letters/${sent.id}`)).statusCode).toBe(404);
    expect((await c.post(`/letters/${sent.id}/trash`)).statusCode).toBe(404);
    // 도착 전에는 받는 사람도 못 본다
    expect((await b.get(`/letters/${sent.id}`)).statusCode).toBe(404);
  });
});

// ───────── 사진 ─────────

async function jpeg(w: number, h: number): Promise<Buffer> {
  // 노이즈가 많은 큰 사진 + EXIF(GPS 포함)
  const noise = Buffer.alloc(w * h * 3);
  for (let i = 0; i < noise.length; i++) noise[i] = (i * 2654435761) >>> 24;
  return sharp(noise, { raw: { width: w, height: h, channels: 3 } })
    .jpeg({ quality: 95 })
    .withExif({ IFD0: { Make: 'GoatPhone', Software: 'test' }, IFD3: { GPSLatitudeRef: 'N' } })
    .toBuffer();
}

async function upload(u: TestUser, file: Buffer, type = 'image/jpeg'): Promise<string> {
  const boundary = '----meeil';
  const payload = Buffer.concat([
    Buffer.from(
      `--${boundary}\r\nContent-Disposition: form-data; name="photo"; filename="p.jpg"\r\nContent-Type: ${type}\r\n\r\n`,
    ),
    file,
    Buffer.from(`\r\n--${boundary}--\r\n`),
  ]);
  const res = await app.inject({
    method: 'POST',
    url: '/photos',
    headers: {
      authorization: `Bearer ${u.token}`,
      'content-type': `multipart/form-data; boundary=${boundary}`,
    },
    payload,
  });
  expect(res.statusCode, res.body).toBe(201);
  return res.json<{ photoId: string }>().photoId;
}

describe('사진', () => {
  it('EXIF 제거·긴 변 1280·WebP·500KB 이내, 서명 URL로만 열린다', async () => {
    const { withGoat } = await regionsAt(T0);
    const a = await makeUser('사진작가', withGoat[0]!);
    const b = await makeUser('사진감상', withGoat[0]!);
    const original = await jpeg(3000, 2000);
    expect((await sharp(original).metadata()).exif).toBeDefined();

    const photoId = await upload(a, original);
    const row = await db.letterPhoto.findUniqueOrThrow({ where: { id: photoId } });
    expect(Math.max(row.width, row.height)).toBe(1280);
    expect(row.bytes).toBeLessThanOrEqual(500 * 1024);

    const sent = (
      await a.post('/letters', letter({ recipientId: b.id, photoId }))
    ).json<LetterDto>();
    await jump(Date.parse(sent.etaAt!) + 1000, a, b);
    const got = (await b.get(`/letters/${sent.id}`)).json<LetterDto>();
    expect(got.photo).toMatchObject({ width: row.width, height: row.height, blurred: false });

    const url = new URL(got.photo!.url);
    const ok = await app.inject({ method: 'GET', url: url.pathname + url.search });
    expect(ok.statusCode).toBe(200);
    expect(ok.headers['content-type']).toBe('image/webp');
    const meta = await sharp(ok.rawPayload).metadata();
    expect(meta.format).toBe('webp');
    expect(meta.exif).toBeUndefined();

    // 서명이 틀리거나 만료되면 403
    const forged = await app.inject({
      method: 'GET',
      url: url.pathname + url.search.replace(/sig=./, 'sig=x'),
    });
    expect(forged.statusCode).toBe(403);
    await jump(clock.now().getTime() + 16 * 60_000);
    const expired = await app.inject({ method: 'GET', url: url.pathname + url.search });
    expect(expired.statusCode).toBe(403);
  });

  it('사진이 아닌 파일은 거절, 남이 올린 사진은 붙일 수 없다', async () => {
    const { withGoat } = await regionsAt(T0);
    const a = await makeUser('파일확인', withGoat[0]!);
    const b = await makeUser('남의사진', withGoat[0]!);
    const boundary = '----meeil';
    const res = await app.inject({
      method: 'POST',
      url: '/photos',
      headers: {
        authorization: `Bearer ${a.token}`,
        'content-type': `multipart/form-data; boundary=${boundary}`,
      },
      payload: `--${boundary}\r\nContent-Disposition: form-data; name="photo"; filename="x.txt"\r\nContent-Type: image/jpeg\r\n\r\nnot an image\r\n--${boundary}--\r\n`,
    });
    expect(res.statusCode).toBe(400);
    expect(res.json()).toMatchObject({ error: { code: 'PHOTO_INVALID' } });

    const bPhoto = await upload(b, await jpeg(200, 200));
    const steal = await a.post('/letters', letter({ recipientId: b.id, photoId: bPhoto }));
    expect(steal.json()).toMatchObject({ error: { code: 'PHOTO_NOT_FOUND' } });
    expect(await points(a.id)).toBe(5);
  });
});

describe('편지지', () => {
  it('가입하면 크림만 가지고 있다', async () => {
    const r = (await db.region.findFirstOrThrow()).code;
    const a = await makeUser('편지지확인', r);
    const res = (await a.get('/stationery')).json<{
      stationery: { id: string; owned: boolean }[];
    }>();
    expect(res.stationery.map((s) => [s.id, s.owned])).toEqual([
      ['cream', true],
      ['lined', false],
      ['sky-cloud', false],
    ]);
  });
});

describe('닉네임 검색', () => {
  it('정확히 일치를 먼저, 그다음 앞부분 일치. 나는 빼고, 비공개 정보는 없다', async () => {
    const r = (await db.region.findFirstOrThrow()).code;
    const me = await makeUser('염소', r);
    await makeUser('염소왕', r);
    await makeUser('염소', r).catch(() => undefined); // 같은 이름은 가입 단계에서 막힘
    const other = await makeUser('Goat', r);
    await makeUser('염소편지', r);
    const res = (await me.get(`/users/search?nick=${encodeURIComponent('염소')}`)).json<{
      users: { id: string; nickname: string }[];
    }>();
    expect(res.users.map((u) => u.nickname)).toEqual(['염소왕', '염소편지']);
    const goat = (await me.get('/users/search?nick=goat')).json<{ users: { id: string }[] }>();
    expect(goat.users[0]!.id).toBe(other.id);
    expect(JSON.stringify(goat)).not.toMatch(/birth|provider|email/);
  });
});

describe('염소 도착 알림', () => {
  it('우리 시에 염소가 막 도착하면 알리고, 6시간 안에는 다시 보내지 않는다', async () => {
    const stop = await db.goatScheduleStop.findFirstOrThrow({
      where: { arriveAt: { gt: T0 }, goat: { kind: 'DELIVERY' } },
      orderBy: { arriveAt: 'asc' },
      include: { goat: true },
    });
    const u = await makeUser('알림받기', stop.regionCode);
    const quiet = await makeUser('토큰없음', stop.regionCode);
    await db.fcmToken.create({ data: { token: 'tok-'.padEnd(40, 'x'), userId: u.id } });
    const at = new Date(stop.arriveAt.getTime() + 60_000);
    expect(await notifyGoatArrivals(db, pusher, at, 5 * 60_000)).toBe(1);
    expect(pusher.sent[0]).toMatchObject({
      userId: u.id,
      msg: { title: '우체부 염소가 왔어요!' },
    });
    expect(pusher.sent.some((p) => p.userId === quiet.id)).toBe(false);
    expect(await notifyGoatArrivals(db, pusher, at, 5 * 60_000)).toBe(0);
  });

  it('푸시 토큰 등록은 로그인한 사용자 것으로', async () => {
    const r = (await db.region.findFirstOrThrow()).code;
    const a = await makeUser('토큰주인', r);
    const res = await app.inject({
      method: 'PUT',
      url: '/me/fcm-token',
      headers: { authorization: `Bearer ${a.token}` },
      payload: { token: 'fcm-token-'.padEnd(60, 'y') },
    });
    expect(res.statusCode).toBe(204);
    expect(await db.fcmToken.count({ where: { userId: a.id } })).toBe(1);
  });
});
