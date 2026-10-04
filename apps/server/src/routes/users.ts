import type { FastifyPluginAsync } from 'fastify';
import { z } from 'zod';
import { nicknameKey, normalizeNickname } from '../domain/nickname.js';
import { parse } from '../errors.js';

const Query = z.object({ nick: z.string().min(1).max(20) });
const TokenBody = z.object({ token: z.string().min(20).max(4096) });

/** 닉네임 검색(SPEC 5.2): 정확히 일치를 먼저, 그다음 앞부분 일치. 공개 정보(닉네임·칭호)만. */
export const userRoutes: FastifyPluginAsync = async (app) => {
  app.addHook('preHandler', app.authenticate);

  app.get('/users/search', async (req) => {
    const { nick } = parse(Query, req.query);
    const key = nicknameKey(nick);
    const visible = {
      id: { not: req.userId },
      status: { in: ['ACTIVE' as const, 'SUSPENDED' as const] },
      nickname: { not: null },
      blocking: { none: { blockedId: req.userId } },
      blockedBy: { none: { blockerId: req.userId } },
    };
    const select = {
      id: true,
      nickname: true,
      titleAchievement: { select: { titleText: true } },
    } as const;
    const [exact, prefix] = await Promise.all([
      app.db.user.findFirst({ where: { ...visible, nicknameKey: key }, select }),
      app.db.user.findMany({
        where: { ...visible, nicknameKey: { startsWith: key, not: key } },
        select,
        orderBy: { nicknameKey: 'asc' },
        take: 20,
      }),
    ]);
    const users = [...(exact ? [exact] : []), ...prefix].map((u) => ({
      id: u.id,
      nickname: u.nickname,
      title: u.titleAchievement?.titleText ?? null,
    }));
    return { query: normalizeNickname(nick), users };
  });

  // 편지지 목록과 내가 가진 것(SPEC 7.2)
  app.get('/stationery', async (req) => {
    const [all, mine] = await Promise.all([
      app.db.stationery.findMany({ orderBy: { sortOrder: 'asc' } }),
      app.db.userStationery.findMany({
        where: { userId: req.userId },
        select: { stationeryId: true },
      }),
    ]);
    const owned = new Set(mine.map((m) => m.stationeryId));
    return {
      stationery: all.map((s) => ({
        id: s.id,
        name: s.name,
        unlockHint: s.unlockHint,
        owned: owned.has(s.id),
      })),
    };
  });

  // 푸시 토큰 등록/해제(기기 하나에 토큰 하나, 계정을 바꾸면 소유자가 바뀐다)
  app.put('/me/fcm-token', async (req, reply) => {
    const { token } = parse(TokenBody, req.body);
    await app.db.fcmToken.upsert({
      where: { token },
      create: { token, userId: req.userId },
      update: { userId: req.userId },
    });
    return reply.status(204).send();
  });
  app.delete('/me/fcm-token', async (req, reply) => {
    const { token } = parse(TokenBody, req.body);
    await app.db.fcmToken.deleteMany({ where: { token, userId: req.userId } });
    return reply.status(204).send();
  });
};
