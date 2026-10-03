import type { FastifyPluginAsync, FastifyRequest } from 'fastify';
import fp from 'fastify-plugin';
import { AppError, unauthorized } from '../errors.js';
import type { TokenService } from './tokens.js';

declare module 'fastify' {
  interface FastifyInstance {
    tokens: TokenService;
    /** preHandler: Bearer access 토큰을 검증하고 request.userId를 채운다 */
    authenticate: (req: FastifyRequest) => Promise<void>;
  }
  interface FastifyRequest {
    userId: string;
  }
}

const plugin: FastifyPluginAsync<{ tokens: TokenService }> = async (app, { tokens }) => {
  app.decorate('tokens', tokens);
  app.decorateRequest('userId', '');
  app.decorate('authenticate', async (req: FastifyRequest) => {
    const header = req.headers.authorization;
    if (!header?.startsWith('Bearer ')) throw unauthorized();
    const userId = await tokens.verifyAccess(header.slice(7));
    const user = await app.db.user.findUnique({ where: { id: userId }, select: { status: true } });
    if (!user || user.status === 'DELETED') throw unauthorized();
    if (user.status === 'BANNED') throw new AppError(403, 'BANNED', '이용이 정지된 계정이에요.');
    req.userId = userId;
  });
};

export const authPlugin = fp(plugin, { name: 'auth' });
