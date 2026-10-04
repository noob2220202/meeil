import type { FastifyPluginAsync } from 'fastify';
import { z } from 'zod';
import { parse } from '../errors.js';
import { BODY_MAX, STICKER_IDS, STICKERS_MAX } from '../letters/rules.js';
import type { LetterService } from '../letters/service.js';

const Hand = z
  .object({
    mode: z.enum(['DIRECT', 'RANDOM', 'REPLY']),
    recipientId: z.string().uuid().optional(),
    replyToId: z.string().uuid().optional(),
    randomScope: z.enum(['NATION', 'PROVINCE', 'CITY']).optional(),
    body: z
      .string()
      .transform((s) => s.normalize('NFC').trim())
      .refine((s) => s.length > 0, '편지에 한 마디라도 적어 주세요.')
      .refine((s) => [...s].length <= BODY_MAX, `편지는 ${BODY_MAX}자까지 쓸 수 있어요.`),
    stationeryId: z.string().min(1).max(40),
    stickers: z
      .array(
        z.object({
          id: z.enum(STICKER_IDS),
          x: z.number().min(0).max(1),
          y: z.number().min(0).max(1),
        }),
      )
      .max(STICKERS_MAX, `스티커는 ${STICKERS_MAX}개까지 붙일 수 있어요.`)
      .default([]),
    photoId: z.string().uuid().optional(),
    clientRequestId: z.string().min(8).max(64),
  })
  .refine((b) => b.mode !== 'DIRECT' || b.recipientId, {
    message: '받는 사람을 골라 주세요.',
  })
  .refine((b) => b.mode !== 'REPLY' || b.replyToId, { message: '답장할 편지가 없어요.' });

const ListQuery = z.object({
  cursor: z.string().uuid().optional(),
  limit: z.coerce.number().int().min(1).max(50).default(30),
});
const IdParam = z.object({ id: z.string().uuid() });

export const letterRoutes: FastifyPluginAsync<{ letters: LetterService }> = async (
  app,
  { letters },
) => {
  app.addHook('preHandler', app.authenticate);

  // 편지 맡기기(SPEC 3.3). 1P 차감, 배정 염소·도착 시각이 정해진다.
  app.post(
    '/letters',
    { config: { rateLimit: { max: 30, timeWindow: '1 minute' } } },
    async (req, reply) => {
      const input = parse(Hand, req.body);
      const letter = await letters.hand(req.userId, input);
      return reply.status(201).send(letter);
    },
  );

  for (const box of ['inbox', 'sent', 'trash'] as const) {
    app.get(`/letters/${box}`, async (req) => {
      const { cursor, limit } = parse(ListQuery, req.query);
      return letters.list(req.userId, box, cursor, limit);
    });
  }

  app.get('/letters/unread-count', async (req) => ({
    count: await letters.unreadCount(req.userId),
  }));

  app.get('/letters/:id', async (req) => letters.get(req.userId, parse(IdParam, req.params).id));
  app.post('/letters/:id/read', async (req) =>
    letters.markRead(req.userId, parse(IdParam, req.params).id),
  );
  app.post('/letters/:id/trash', async (req) =>
    letters.trash(req.userId, parse(IdParam, req.params).id),
  );
  app.post('/letters/:id/restore', async (req) =>
    letters.restore(req.userId, parse(IdParam, req.params).id),
  );
  app.delete('/letters/:id', async (req, reply) => {
    await letters.purge(req.userId, parse(IdParam, req.params).id);
    return reply.status(204).send();
  });
};
