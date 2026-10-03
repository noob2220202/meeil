import type { FastifyPluginAsync } from 'fastify';
import { z } from 'zod';
import { parse } from '../errors.js';
import { BODY_MAX, STICKER_IDS, STICKERS_MAX } from '../letters/rules.js';
import type { RollingService } from '../rolling/service.js';

const Level = z.object({ level: z.enum(['NATION', 'PROVINCE', 'CITY']) });
const IdParam = z.object({ id: z.string().uuid() });
const Entry = z.object({
  body: z
    .string()
    .transform((s) => s.normalize('NFC').trim())
    .refine((s) => s.length > 0, '한 마디라도 적어 주세요.')
    .refine((s) => [...s].length <= BODY_MAX, `${BODY_MAX}자까지 쓸 수 있어요.`),
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
  // 롤링페이퍼는 사진 불가(SPEC 6) — 사진 필드가 오면 거절
  photoId: z.undefined({ error: '롤링페이퍼에는 사진을 붙일 수 없어요.' }).optional(),
});

/** 롤링페이퍼 (SPEC 11.5: GET /rolling/current?level=, POST /rolling/:id/entries) */
export const rollingRoutes: FastifyPluginAsync<{ rolling: RollingService }> = async (
  app,
  { rolling },
) => {
  app.addHook('preHandler', app.authenticate);

  app.get('/rolling/current', async (req) =>
    rolling.current(req.userId, parse(Level, req.query).level),
  );

  /** 롤링 탭 한 번에: 전국·도·시 이번 장 요약 */
  app.get('/rolling/current/all', async (req) => {
    const out: Record<string, unknown> = {};
    for (const level of ['NATION', 'PROVINCE', 'CITY'] as const) {
      try {
        const v = await rolling.current(req.userId, level);
        out[level] = { ...v, entries: undefined, entryCount: v.entries.length };
      } catch (e) {
        out[level] = { error: (e as { code?: string }).code ?? 'ERROR' };
      }
    }
    return out;
  });

  app.get('/rolling/album', async (req) => rolling.album(req.userId));

  app.get('/rolling/:id', async (req) => rolling.get(req.userId, parse(IdParam, req.params).id));

  app.post(
    '/rolling/:id/entries',
    { config: { rateLimit: { max: 20, timeWindow: '1 minute' } } },
    async (req, reply) => {
      const { id } = parse(IdParam, req.params);
      const { body, stickers } = parse(Entry, req.body);
      return reply.status(201).send(await rolling.join(req.userId, id, { body, stickers }));
    },
  );
};
