import type { FastifyPluginAsync } from 'fastify';
import { z } from 'zod';
import { AppError, parse } from '../errors.js';
import type { LedgerReason } from '../generated/prisma/client.js';
import type { AdRewardService } from '../rewards/ads.js';
import type { AchievementService } from '../rewards/achievements.js';
import type { AttendanceService } from '../rewards/attendance.js';
import { METRICS } from '../rewards/achievements.js';

export interface RewardDeps {
  attendance: AttendanceService;
  ads: AdRewardService;
  achievements: AchievementService;
  /** 개발용 광고 보상(/ads/dev-reward). production에서는 꺼진다 */
  devAds: boolean;
}

/** 원장 사유 → 내역 화면 문구 */
export const LEDGER_LABELS: Record<LedgerReason, string> = {
  SIGNUP_BONUS: '가입 선물',
  ATTENDANCE: '출석 체크',
  ATTENDANCE_STREAK: '7일 연속 출석 보너스',
  AD_REWARD: '광고 보상',
  ACHIEVEMENT: '업적 달성',
  LETTER_SEND: '편지 맡기기',
  LETTER_REFUND: '편지 환불',
  ADMIN_ADJUST: '운영자 조정',
};

const Month = z.object({
  month: z
    .string()
    .regex(/^\d{4}-(0[1-9]|1[0-2])$/)
    .optional(),
});
const Cursor = z.object({ cursor: z.string().uuid().optional() });
const Seen = z.object({ ids: z.array(z.string().max(40)).max(50) });
const Title = z.object({ achievementId: z.string().max(40).nullable() });

/** 포인트·출석·광고·업적 (SPEC 7, 11.5) */
export const rewardRoutes: FastifyPluginAsync<RewardDeps> = async (app, deps) => {
  const { attendance, ads, achievements } = deps;

  /**
   * AdMob SSV 콜백. 구글이 GET으로 부른다(인증 없음, 서명으로 검증).
   * 서명이 맞으면 상한·중복이어도 200을 돌려 구글이 재시도하지 않게 한다.
   */
  app.get('/ads/reward-callback', async (req, reply) => {
    const raw = req.raw.url ?? '';
    const q = raw.includes('?') ? raw.slice(raw.indexOf('?') + 1) : '';
    // 콘솔의 "확인" 버튼은 서명 없이 부른다
    if (q === '') return reply.status(200).send({ ok: true });
    const r = await ads.handleCallback(q);
    if (!r.ok) {
      req.log.warn({ error: r.error }, 'ad reward callback rejected');
      return reply
        .status(r.error === 'BAD_SIGNATURE' ? 403 : 400)
        .send({ ok: false, error: r.error });
    }
    return { ok: true, granted: r.granted };
  });

  await app.register(async (authed) => {
    authed.addHook('preHandler', app.authenticate);

    authed.get('/attendance', async (req) =>
      attendance.status(req.userId, parse(Month, req.query).month),
    );

    authed.post('/attendance', async (req) => {
      const r = await attendance.check(req.userId);
      if (r.checkedIn) await achievements.evaluateSafe(req.userId, METRICS.attendance, req.log);
      return r;
    });

    authed.get('/ads/status', async (req) => ads.status(req.userId));

    if (deps.devAds) {
      /** 개발 빌드 전용: 테스트 광고는 SSV 콜백이 오지 않으므로 같은 지급 경로를 직접 부른다 */
      authed.post('/ads/dev-reward', async (req) => {
        const r = await ads.grant(req.userId, `ad-dev:${crypto.randomUUID()}`);
        return { ...r, ...(await ads.status(req.userId)) };
      });
    }

    authed.get('/points/history', async (req) => {
      const { cursor } = parse(Cursor, req.query);
      const limit = 30;
      const rows = await app.db.pointsLedger.findMany({
        where: { userId: req.userId },
        orderBy: [{ createdAt: 'desc' }, { id: 'desc' }],
        take: limit + 1,
        ...(cursor ? { cursor: { id: cursor }, skip: 1 } : {}),
      });
      const page = rows.slice(0, limit);
      return {
        entries: page.map((e) => ({
          id: e.id,
          delta: e.delta,
          balanceAfter: e.balanceAfter,
          reason: e.reason,
          label: LEDGER_LABELS[e.reason],
          createdAt: e.createdAt.toISOString(),
        })),
        nextCursor: rows.length > limit ? page[page.length - 1]!.id : null,
      };
    });

    authed.get('/achievements', async (req) => achievements.list(req.userId));

    authed.get('/achievements/unseen', async (req) => ({
      achievements: await achievements.unseen(req.userId),
    }));

    authed.post('/achievements/seen', async (req) => {
      await achievements.markSeen(req.userId, parse(Seen, req.body).ids);
      return { ok: true };
    });

    /** 칭호 고르기(달성한 업적의 칭호만). null이면 떼기 */
    authed.put('/me/title', async (req) => {
      const { achievementId } = parse(Title, req.body);
      if (achievementId) {
        const owned = await app.db.userAchievement.findUnique({
          where: { userId_achievementId: { userId: req.userId, achievementId } },
          include: { achievement: true },
        });
        if (!owned?.achievement.titleText) {
          throw new AppError(400, 'TITLE_LOCKED', '아직 얻지 못한 칭호예요.');
        }
      }
      await app.db.user.update({
        where: { id: req.userId },
        data: { titleAchievementId: achievementId },
      });
      return { titleAchievementId: achievementId };
    });
  });
};
