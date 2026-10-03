import cors from '@fastify/cors';
import Fastify, { type FastifyInstance } from 'fastify';
import type { Db } from './db.js';
import type { Env } from './env.js';
import { healthRoutes } from './routes/health.js';
import { regionRoutes } from './routes/regions.js';

declare module 'fastify' {
  interface FastifyInstance {
    db: Db;
  }
}

export interface AppOptions {
  env: Env;
  db: Db;
  logger?: boolean;
}

export async function buildApp({ env, db, logger = true }: AppOptions): Promise<FastifyInstance> {
  const app = Fastify({
    logger: logger ? { level: env.NODE_ENV === 'production' ? 'info' : 'debug' } : false,
    trustProxy: true,
  });

  app.decorate('db', db);
  await app.register(cors, { origin: env.CORS_ORIGINS.length > 0 ? env.CORS_ORIGINS : false });

  // 공통 오류 응답 형태: { error: { code, message } }
  app.setErrorHandler(
    (err: { statusCode?: number; code?: string; message: string }, req, reply) => {
      const status = err.statusCode && err.statusCode >= 400 ? err.statusCode : 500;
      if (status >= 500) req.log.error(err);
      void reply.status(status).send({
        error: {
          code: err.code ?? (status >= 500 ? 'INTERNAL' : 'BAD_REQUEST'),
          message:
            status >= 500 ? '서버에 문제가 생겼어요. 잠시 후 다시 시도해 주세요.' : err.message,
        },
      });
    },
  );
  app.setNotFoundHandler((_req, reply) => {
    void reply.status(404).send({ error: { code: 'NOT_FOUND', message: '찾을 수 없어요.' } });
  });

  await app.register(healthRoutes);
  await app.register(regionRoutes);
  return app;
}
