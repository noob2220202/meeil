import cors from '@fastify/cors';
import rateLimit from '@fastify/rate-limit';
import Fastify, { type FastifyInstance } from 'fastify';
import { authPlugin } from './auth/plugin.js';
import { createSocialVerifier, type SocialVerifier } from './auth/social.js';
import { TokenService } from './auth/tokens.js';
import type { Db } from './db.js';
import { adminSecretKey, type Env } from './env.js';
import { AppError } from './errors.js';
import { authRoutes } from './routes/auth.js';
import { goatRoutes } from './routes/goats.js';
import { letterRoutes } from './routes/letters.js';
import { mediaRoutes, photoRoutes } from './routes/photos.js';
import { rollingRoutes } from './routes/rolling.js';
import { userRoutes } from './routes/users.js';
import { RollingService } from './rolling/service.js';
import { LetterService } from './letters/service.js';
import { noopModerator, type PhotoModerator } from './photos/process.js';
import { FcmPusher, LogPusher, MemoryPusher, type Pusher } from './push/push.js';
import { LocalStorage, R2Storage, type Storage } from './storage/storage.js';
import { healthRoutes } from './routes/health.js';
import { meRoutes } from './routes/me.js';
import { regionRoutes } from './routes/regions.js';
import { ScheduleService } from './schedule/service.js';
import { AdminTokens, adminAuthPlugin } from './admin/auth.js';
import { adminRoutes } from './admin/routes.js';
import { EatService } from './moderation/eat.js';
import { ReportService } from './moderation/reports.js';
import { safetyRoutes } from './routes/safety.js';
import { webRoutes } from './routes/web.js';
import { AccountService } from './account/delete.js';
import { clientErrorRoutes } from './routes/client-errors.js';
import { rewardRoutes } from './routes/rewards.js';
import { AchievementService } from './rewards/achievements.js';
import { AdRewardService, GoogleAdKeys, type AdKeySource } from './rewards/ads.js';
import { AttendanceService } from './rewards/attendance.js';
import { registerSecurityHeaders } from './lib/security-headers.js';

declare module 'fastify' {
  interface FastifyInstance {
    db: Db;
    letters: LetterService;
    eat: EatService;
    account: AccountService;
    /** 등록된 모든 라우트(보안 점검 테스트가 인증 누락을 찾는 데 쓴다) */
    routeList: { method: string; url: string }[];
  }
}

export function createStorage(env: Env, now: () => Date = () => new Date()): Storage {
  if (env.STORAGE_DRIVER === 'r2') {
    return new R2Storage(
      env.R2_ACCOUNT_ID,
      env.R2_ACCESS_KEY_ID,
      env.R2_SECRET_ACCESS_KEY,
      env.R2_BUCKET,
    );
  }
  return new LocalStorage(
    env.LOCAL_STORAGE_DIR,
    env.PUBLIC_BASE_URL,
    env.MEDIA_SIGNING_SECRET ?? `media:${env.JWT_SECRET}`,
    now,
  );
}

export function createPusher(env: Env, db: Db): Pusher {
  if (env.FCM_PROJECT_ID && env.FCM_CLIENT_EMAIL && env.FCM_PRIVATE_KEY) {
    return new FcmPusher(db, {
      projectId: env.FCM_PROJECT_ID,
      clientEmail: env.FCM_CLIENT_EMAIL,
      privateKey: env.FCM_PRIVATE_KEY,
    });
  }
  if (env.NODE_ENV === 'test') return new MemoryPusher();
  return new LogPusher((m) => console.info(m));
}

export interface AppOptions {
  env: Env;
  db: Db;
  logger?: boolean;
  /** 테스트에서 소셜 검증·시각을 바꿔 끼운다 */
  social?: SocialVerifier;
  now?: () => Date;
  schedule?: ScheduleService;
  storage?: Storage;
  pusher?: Pusher;
  moderate?: PhotoModerator;
  /** 요청 제한. 테스트에서만 끈다 */
  rateLimit?: boolean;
  /** AdMob SSV 공개키(테스트에서 바꿔 끼운다) */
  adKeys?: AdKeySource;
}

export async function buildApp({
  env,
  db,
  logger = true,
  social,
  now = () => new Date(),
  rateLimit: rateLimitEnabled = true,
  schedule = new ScheduleService(db),
  storage = createStorage(env, now),
  pusher = createPusher(env, db),
  moderate = noopModerator,
  adKeys = new GoogleAdKeys(),
}: AppOptions): Promise<FastifyInstance> {
  const app = Fastify({
    logger: logger ? { level: env.NODE_ENV === 'production' ? 'info' : 'debug' } : false,
    // 요청당 로그 두 줄(incoming·completed) 대신 아래 onResponse에서 한 줄만 남긴다(부하 테스트: 로그 쓰기가 CPU의 7%)
    disableRequestLogging: true,
    // true(가장 왼쪽 값을 믿음)는 X-Forwarded-For 위조로 요청 제한을 피할 수 있다
    trustProxy: (_addr: string, hop: number) => hop < env.TRUST_PROXY_HOPS,
    bodyLimit: 64 * 1024,
  });

  app.decorate('db', db);
  const routeList: { method: string; url: string }[] = [];
  app.decorate('routeList', routeList);
  app.addHook('onRoute', (r) => {
    for (const m of [r.method].flat()) if (m !== 'HEAD') routeList.push({ method: m, url: r.url });
  });
  app.addHook('onResponse', async (req, reply) => {
    if (req.url === '/health') return;
    req.log.info(
      {
        method: req.method,
        url: req.routeOptions.url ?? req.url,
        status: reply.statusCode,
        ms: Math.round(reply.elapsedTime),
      },
      'req',
    );
  });
  registerSecurityHeaders(app, { hsts: env.NODE_ENV === 'production' });
  await app.register(cors, { origin: env.CORS_ORIGINS.length > 0 ? env.CORS_ORIGINS : false });
  await app.register(rateLimit, {
    global: rateLimitEnabled,
    max: 120,
    timeWindow: '1 minute',
    enableDraftSpec: true,
    errorResponseBuilder: (_req, ctx) =>
      new AppError(
        ctx.statusCode,
        'RATE_LIMITED',
        '요청이 너무 많아요. 잠시 후 다시 시도해 주세요.',
      ),
  });

  // 공통 오류 응답 형태: { error: { code, message } }
  app.setErrorHandler(
    (err: { statusCode?: number; code?: string; message: string }, req, reply) => {
      const status = err.statusCode && err.statusCode >= 400 ? err.statusCode : 500;
      if (status >= 500) req.log.error(err);
      const known = err instanceof AppError;
      void reply.status(status).send({
        error: {
          code: known ? err.code : status >= 500 ? 'INTERNAL' : 'BAD_REQUEST',
          message:
            known || status < 500
              ? err.message
              : '서버에 문제가 생겼어요. 잠시 후 다시 시도해 주세요.',
        },
      });
    },
  );
  app.setNotFoundHandler((_req, reply) => {
    void reply.status(404).send({ error: { code: 'NOT_FOUND', message: '찾을 수 없어요.' } });
  });

  await app.register(authPlugin, { tokens: new TokenService(db, env.JWT_SECRET, now) });
  await app.register(healthRoutes);
  await app.register(clientErrorRoutes, { rateLimit: rateLimitEnabled });
  await app.register(regionRoutes);
  await app.register(authRoutes, {
    social:
      social ??
      createSocialVerifier({
        kakaoAppId: env.KAKAO_APP_ID,
        googleClientIds: env.GOOGLE_CLIENT_IDS,
      }),
    devLogin: env.AUTH_DEV_LOGIN,
    rateLimit: rateLimitEnabled,
  });
  const achievements = new AchievementService(db, now);
  const account = new AccountService(db, storage, now);
  app.decorate('account', account);
  await app.register(meRoutes, { now, achievements, account });
  await app.register(webRoutes, { legalDir: env.LEGAL_DIR, rateLimit: rateLimitEnabled });
  await app.register(goatRoutes, {
    schedule,
    now,
    cacheMs: env.NODE_ENV === 'test' ? 0 : 30_000,
  });
  const letters = new LetterService(db, storage, pusher, now, achievements);
  app.decorate('letters', letters);
  await app.register(letterRoutes, { letters });
  await app.register(photoRoutes, { storage, moderate });
  if (storage instanceof LocalStorage) await app.register(mediaRoutes, { storage });
  await app.register(userRoutes);
  await app.register(rollingRoutes, { rolling: new RollingService(db, now, achievements) });
  await app.register(rewardRoutes, {
    attendance: new AttendanceService(db, now),
    ads: new AdRewardService(db, adKeys, now, env.ADMOB_AD_UNIT_IDS),
    achievements,
    devAds: env.AUTH_DEV_LOGIN,
  });
  await app.register(safetyRoutes, {
    reports: new ReportService(db, now),
    rateLimit: rateLimitEnabled,
  });

  const eat = new EatService(db, storage, pusher, now);
  app.decorate('eat', eat);
  await app.register(adminAuthPlugin, { tokens: new AdminTokens(env.JWT_SECRET, now) });
  await app.register(adminRoutes, {
    eat,
    storage,
    pusher,
    now,
    secretKey: adminSecretKey(env),
    account,
    rateLimit: rateLimitEnabled,
  });
  return app;
}
