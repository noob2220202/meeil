import type { FastifyPluginAsync } from 'fastify';

/** 지역 테이블(시도·시). 클라이언트는 경계 데이터를 번들로 갖고 있고, 이 API는 버전 확인·관리자용. */
export const regionRoutes: FastifyPluginAsync = async (app) => {
  app.get('/regions', async () => {
    const [provinces, regions] = await Promise.all([
      app.db.province.findMany({ orderBy: { code: 'asc' } }),
      app.db.region.findMany({
        where: { active: true },
        orderBy: { code: 'asc' },
        select: {
          code: true,
          name: true,
          fullName: true,
          provinceCode: true,
          lon: true,
          lat: true,
          neighbors: true,
          version: true,
        },
      }),
    ]);
    return { version: regions[0]?.version ?? null, provinces, regions };
  });
};
