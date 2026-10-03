import type { FastifyPluginAsync } from 'fastify';
import { z } from 'zod';
import type { Db } from '../db.js';
import { MIN_AGE, ageOn, isValidBirthDate } from '../domain/age.js';
import { judgeRegionReport } from '../domain/region-report.js';
import { toMeDto } from '../domain/me.js';
import {
  NICKNAME_MESSAGES,
  checkNickname,
  nicknameChangeableAt,
  nicknameKey,
  normalizeNickname,
} from '../domain/nickname.js';
import { POINTS, applyLedger } from '../domain/points.js';
import { AppError, parse } from '../errors.js';
import { Prisma } from '../generated/prisma/client.js';

const Body = {
  agreements: z.object({
    terms: z.literal(true, { error: '이용약관에 동의해 주세요.' }),
    privacy: z.literal(true, { error: '개인정보 수집·이용에 동의해 주세요.' }),
  }),
  birthDate: z.object({
    birthDate: z.string().regex(/^\d{4}-\d{2}-\d{2}$/, '생년월일 형식이 올바르지 않아요.'),
  }),
  nickname: z.object({ nickname: z.string().max(40) }),
  nickQuery: z.object({ nick: z.string().max(40) }),
  region: z.object({
    regionCode: z.string().regex(/^\d{5}$/, '지역 코드가 올바르지 않아요.'),
    /** 기기가 감지한 가짜 위치(Android isMocked) */
    mocked: z.boolean().default(false),
  }),
};

/** 약관·생년월일·닉네임이 모두 채워지는 순간 가입 보너스와 기본 편지지를 한 번만 지급한다. */
async function completeOnboardingIfReady(db: Db, userId: string): Promise<void> {
  await db.$transaction(async (tx) => {
    const u = await tx.user.findUniqueOrThrow({ where: { id: userId } });
    if (!u.termsAgreedAt || !u.privacyAgreedAt || !u.birthDate || !u.nickname) return;
    await applyLedger(tx, {
      userId,
      delta: POINTS.SIGNUP_BONUS,
      reason: 'SIGNUP_BONUS',
      idempotencyKey: `signup:${userId}`,
    });
    const defaults = await tx.stationery.findMany({
      where: { isDefault: true },
      select: { id: true },
    });
    await tx.userStationery.createMany({
      data: defaults.map((s) => ({ userId, stationeryId: s.id })),
      skipDuplicates: true,
    });
  });
}

export const meRoutes: FastifyPluginAsync<{ now: () => Date }> = async (app, { now }) => {
  app.addHook('preHandler', app.authenticate);

  const me = async (userId: string) =>
    toMeDto(await app.db.user.findUniqueOrThrow({ where: { id: userId } }));

  app.get('/me', async (req) => {
    await app.db.user.update({ where: { id: req.userId }, data: { lastActiveAt: now() } });
    return me(req.userId);
  });

  app.post('/me/agreements', async (req) => {
    parse(Body.agreements, req.body);
    const at = now();
    await app.db.user.update({
      where: { id: req.userId },
      data: { termsAgreedAt: at, privacyAgreedAt: at },
    });
    await completeOnboardingIfReady(app.db, req.userId);
    return me(req.userId);
  });

  /**
   * 생년월일은 한 번만 입력한다. 만 14세 미만이면 계정과 소셜 연결을 즉시 지운다
   * (아동 개인정보를 보관하지 않기 위함).
   */
  app.post('/me/birthdate', async (req) => {
    const { birthDate } = parse(Body.birthDate, req.body);
    if (!isValidBirthDate(birthDate, now())) {
      throw new AppError(400, 'VALIDATION', '생년월일을 다시 확인해 주세요.');
    }
    const user = await app.db.user.findUniqueOrThrow({ where: { id: req.userId } });
    if (user.birthDate) throw new AppError(409, 'BIRTHDATE_LOCKED', '생년월일은 바꿀 수 없어요.');
    if (ageOn(birthDate, now()) < MIN_AGE) {
      await app.db.user.delete({ where: { id: req.userId } });
      throw new AppError(403, 'UNDER_AGE', `메에일은 만 ${MIN_AGE}세 이상부터 이용할 수 있어요.`);
    }
    await app.db.user.update({
      where: { id: req.userId },
      data: { birthDate: new Date(`${birthDate}T00:00:00.000Z`) },
    });
    await completeOnboardingIfReady(app.db, req.userId);
    return me(req.userId);
  });

  app.get('/nicknames/check', async (req) => {
    const { nick } = parse(Body.nickQuery, req.query);
    const problem = checkNickname(nick);
    if (problem) return { available: false, reason: problem, message: NICKNAME_MESSAGES[problem] };
    const taken = await app.db.user.findFirst({
      where: { nicknameKey: nicknameKey(nick), id: { not: req.userId } },
      select: { id: true },
    });
    if (taken) return { available: false, reason: 'TAKEN', message: NICKNAME_MESSAGES.TAKEN };
    return { available: true, reason: null, message: '멋진 닉네임이에요!' };
  });

  app.put('/me/nickname', async (req) => {
    const { nickname: raw } = parse(Body.nickname, req.body);
    const problem = checkNickname(raw);
    if (problem) throw new AppError(400, `NICKNAME_${problem}`, NICKNAME_MESSAGES[problem]);
    const nickname = normalizeNickname(raw);

    const user = await app.db.user.findUniqueOrThrow({ where: { id: req.userId } });
    if (user.nickname === nickname) return me(req.userId);
    // 처음 정할 때는 제한 없음. 이후 변경은 30일에 1회
    const changeableAt = user.nickname ? nicknameChangeableAt(user.nicknameChangedAt) : null;
    if (changeableAt && changeableAt > now()) {
      throw new AppError(409, 'NICKNAME_TOO_SOON', NICKNAME_MESSAGES.TOO_SOON);
    }
    try {
      await app.db.user.update({
        where: { id: req.userId },
        data: { nickname, nicknameKey: nicknameKey(nickname), nicknameChangedAt: now() },
      });
    } catch (e) {
      if (e instanceof Prisma.PrismaClientKnownRequestError && e.code === 'P2002') {
        throw new AppError(409, 'NICKNAME_TAKEN', NICKNAME_MESSAGES.TAKEN);
      }
      throw e;
    }
    await completeOnboardingIfReady(app.db, req.userId);
    return me(req.userId);
  });

  /**
   * 현재 지역 보고. 기기에서 시를 판정해 코드만 보낸다(SPEC 8).
   * 가짜 위치·비현실적 이동은 기록만 하고 반영하지 않는다.
   */
  app.post('/me/region', async (req) => {
    const { regionCode, mocked } = parse(Body.region, req.body);
    const region = await app.db.region.findFirst({ where: { code: regionCode, active: true } });
    if (!region) throw new AppError(400, 'UNKNOWN_REGION', '알 수 없는 지역이에요.');
    const at = now();
    const user = await app.db.user.findUniqueOrThrow({
      where: { id: req.userId },
      include: { lastRegion: true },
    });
    const reject = judgeRegionReport({
      mocked,
      last:
        user.lastRegion && user.lastRegionReportedAt
          ? { lon: user.lastRegion.lon, lat: user.lastRegion.lat, at: user.lastRegionReportedAt }
          : null,
      next: { lon: region.lon, lat: region.lat },
      now: at,
    });
    await app.db.userRegionReport.create({
      data: {
        userId: req.userId,
        regionCode,
        reportedAt: at,
        accepted: reject === null,
        rejectReason: reject,
      },
    });
    if (reject) {
      return { accepted: false, reason: reject, regionCode: user.lastRegionCode };
    }
    await app.db.$transaction([
      app.db.user.update({
        where: { id: req.userId },
        data: {
          lastRegionCode: regionCode,
          lastRegionReportedAt: at,
          homeRegionCode: user.homeRegionCode ?? regionCode,
        },
      }),
      app.db.regionVisit.upsert({
        where: { userId_regionCode: { userId: req.userId, regionCode } },
        create: { userId: req.userId, regionCode },
        update: {},
      }),
    ]);
    return { accepted: true, reason: null, regionCode };
  });
};
