import type { FastifyPluginAsync } from 'fastify';
import { z } from 'zod';
import { AppError, parse } from '../errors.js';
import { REPORT_REASONS, type ReportService } from '../moderation/reports.js';

const ReportBody = z.object({
  targetType: z.enum(['LETTER', 'ROLLING_ENTRY', 'USER']),
  targetId: z.string().uuid(),
  reason: z.enum(Object.keys(REPORT_REASONS) as [keyof typeof REPORT_REASONS]),
  detail: z
    .string()
    .max(500, '500자까지 쓸 수 있어요.')
    .transform((s) => s.trim())
    .optional(),
});
const BlockBody = z.object({ userId: z.string().uuid() });
const UserParam = z.object({ userId: z.string().uuid() });
const Settings = z
  .object({ randomReceive: z.boolean(), notifyEnabled: z.boolean() })
  .partial()
  .refine((o) => Object.keys(o).length > 0, '바꿀 설정이 없어요.');

/** 신고·차단·설정·공지 (SPEC 9.1, 10) */
export const safetyRoutes: FastifyPluginAsync<{
  reports: ReportService;
  rateLimit: boolean;
}> = async (app, { reports, rateLimit }) => {
  app.addHook('preHandler', app.authenticate);

  app.get('/reports/reasons', async () => ({
    reasons: Object.entries(REPORT_REASONS).map(([code, label]) => ({ code, label })),
  }));

  app.post(
    '/reports',
    rateLimit ? { config: { rateLimit: { max: 10, timeWindow: '1 minute' } } } : {},
    async (req, reply) => {
      const body = parse(ReportBody, req.body);
      const r = await reports.create(req.userId, {
        targetType: body.targetType,
        targetId: body.targetId,
        reason: body.reason,
        ...(body.detail ? { detail: body.detail } : {}),
      });
      return reply.status(r.duplicate ? 200 : 201).send(r);
    },
  );

  app.get('/blocks', async (req) => {
    const rows = await app.db.block.findMany({
      where: { blockerId: req.userId },
      include: { blocked: { select: { id: true, nickname: true } } },
      orderBy: { createdAt: 'desc' },
    });
    return {
      blocks: rows.map((b) => ({
        userId: b.blocked.id,
        nickname: b.blocked.nickname,
        blockedAt: b.createdAt.toISOString(),
      })),
    };
  });

  /** 차단: 상대의 편지·롤링 글이 내게 보이지 않고, 상대는 나를 찾거나 랜덤으로 만날 수 없다 */
  app.post('/blocks', async (req, reply) => {
    const { userId } = parse(BlockBody, req.body);
    if (userId === req.userId) throw new AppError(400, 'SELF_BLOCK', '나를 차단할 수는 없어요.');
    const target = await app.db.user.findUnique({ where: { id: userId }, select: { id: true } });
    if (!target) throw new AppError(404, 'USER_NOT_FOUND', '사용자를 찾을 수 없어요.');
    await app.db.block.createMany({
      data: [{ blockerId: req.userId, blockedId: userId }],
      skipDuplicates: true,
    });
    return reply.status(201).send({ userId, blocked: true });
  });

  app.delete('/blocks/:userId', async (req) => {
    const { userId } = parse(UserParam, req.params);
    await app.db.block.deleteMany({ where: { blockerId: req.userId, blockedId: userId } });
    return { userId, blocked: false };
  });

  app.put('/me/settings', async (req) => {
    const s = parse(Settings, req.body);
    const u = await app.db.user.update({
      where: { id: req.userId },
      data: s,
      select: { randomReceive: true, notifyEnabled: true },
    });
    return u;
  });

  app.get('/notices', async () => {
    const rows = await app.db.notice.findMany({
      where: { publishedAt: { not: null } },
      orderBy: [{ pinned: 'desc' }, { publishedAt: 'desc' }],
      take: 50,
    });
    return {
      notices: rows.map((n) => ({
        id: n.id,
        title: n.title,
        body: n.body,
        pinned: n.pinned,
        publishedAt: n.publishedAt!.toISOString(),
      })),
    };
  });
};
