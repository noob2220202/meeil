import cors from '@fastify/cors';
import rateLimit from '@fastify/rate-limit';
import Fastify, { type FastifyInstance } from 'fastify';
import { authPlugin } from './auth/plugin.js';
import { createSocialVerifier, type SocialVerifier } from './auth/social.js';
import { TokenService } from './auth/tokens.js';
import type { Db } from './db.js';
import type { Env } from './env.js';
import { AppError } from './errors.js';
import { authRoutes } from './routes/auth.js';
import { goatRoutes } from './routes/goats.js';
import { healthRoutes } from './routes/health.js';
import { meRoutes } from './routes/me.js';
import { regionRoutes } from './routes/regions.js';
import { ScheduleService } from './schedule/service.js';

declare module 'fastify' {
  interface FastifyInstance {
    db: Db;
  }
}

export interface AppOptions {
  env: Env;
  db: Db;
  logger?: boolean;
  /** 테스트에서 소셜 검증·시각을 바꿔 끼운다 */
  social?: SocialVerifier;
  now?: () => Date;
  schedule?: ScheduleService;
  /** 요청 제한. 테스트에서만 끈다 */
  rateLimit?: boolean;
}

export async function buildApp({
  env,
  db,
  logger = true,
  social,
  now = () => new Date(),
  rateLimit: rateLimitEnabled = true,
  schedule = new ScheduleService(db),
}: AppOptions): Promise<FastifyInstance> {
  const app = Fastify({
    logger: logger ? { level: env.NODE_ENV === 'production' ? 'info' : 'debug' } : false,
    trustProxy: true,
    bodyLimit: 64 * 1024,
  });

  app.decorate('db', db);
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
  await app.register(meRoutes, { now });
  await app.register(goatRoutes, { schedule, now });
  return app;
}
