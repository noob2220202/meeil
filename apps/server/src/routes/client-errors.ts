import type { FastifyPluginAsync } from 'fastify';
import { z } from 'zod';
import { parse } from '../errors.js';

const Body = z.object({
  message: z.string().max(500),
  stack: z.string().max(4000).default(''),
  source: z.string().max(80).nullish(),
  platform: z.string().max(20),
  mode: z.enum(['release', 'profile', 'debug']),
  appVersion: z.string().max(20).optional(),
});

/**
 * 앱 오류 요약 받기(M7). 로그로만 남기고 저장하지 않는다. 사용자 식별 정보는 받지 않는다.
 * 앱은 같은 오류를 한 번, 1분에 5건까지만 보낸다.
 */
export const clientErrorRoutes: FastifyPluginAsync<{ rateLimit: boolean }> = async (app, opts) => {
  app.post(
    '/client-errors',
    opts.rateLimit ? { config: { rateLimit: { max: 10, timeWindow: '1 minute' } } } : {},
    async (req, reply) => {
      const b = parse(Body, req.body);
      req.log.warn({ clientError: b }, 'client error');
      return reply.status(202).send({ ok: true });
    },
  );
};
