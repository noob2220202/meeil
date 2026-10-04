import type { FastifyPluginAsync } from 'fastify';

export const healthRoutes: FastifyPluginAsync = async (app) => {
  app.get('/health', async () => {
    await app.db.$queryRaw`SELECT 1`;
    return { ok: true, time: new Date().toISOString() };
  });
};
