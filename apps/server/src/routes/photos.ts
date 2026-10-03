import multipart from '@fastify/multipart';
import type { FastifyPluginAsync } from 'fastify';
import { AppError } from '../errors.js';
import { MAX_UPLOAD_BYTES, processPhoto, type PhotoModerator } from '../photos/process.js';
import type { LocalStorage, Storage } from '../storage/storage.js';

/**
 * 사진 올리기(SPEC 5.1). 서버에서 EXIF 제거·리사이즈·WebP 변환 후 비공개 저장소에 둔다.
 * 편지를 맡길 때 photoId로 연결한다.
 */
export const photoRoutes: FastifyPluginAsync<{
  storage: Storage;
  moderate: PhotoModerator;
}> = async (app, { storage, moderate }) => {
  await app.register(multipart, { limits: { fileSize: MAX_UPLOAD_BYTES, files: 1, fields: 0 } });

  app.post(
    '/photos',
    {
      preHandler: app.authenticate,
      config: { rateLimit: { max: 20, timeWindow: '10 minutes' } },
    },
    async (req, reply) => {
      const file = await req.file();
      if (!file) throw new AppError(400, 'PHOTO_MISSING', '사진을 골라 주세요.');
      let raw: Buffer;
      try {
        raw = await file.toBuffer();
      } catch {
        throw new AppError(413, 'PHOTO_TOO_LARGE', '사진이 너무 커요(10MB까지).');
      }
      const photo = await processPhoto(raw);
      if ((await moderate(photo.webp)) === 'reject') {
        throw new AppError(400, 'PHOTO_REJECTED', '이 사진은 보낼 수 없어요.');
      }
      const row = await app.db.letterPhoto.create({
        data: {
          uploaderId: req.userId,
          storageKey: 'pending',
          width: photo.width,
          height: photo.height,
          bytes: photo.bytes,
        },
      });
      const key = `letters/${row.id}.webp`;
      await storage.put(key, photo.webp, 'image/webp');
      await app.db.letterPhoto.update({ where: { id: row.id }, data: { storageKey: key } });
      return reply.status(201).send({
        photoId: row.id,
        width: photo.width,
        height: photo.height,
        bytes: photo.bytes,
      });
    },
  );
};

/** local 드라이버 전용: 서명이 맞을 때만 파일을 내준다 */
export const mediaRoutes: FastifyPluginAsync<{ storage: LocalStorage }> = async (
  app,
  { storage },
) => {
  app.get('/media/*', async (req, reply) => {
    const key = (req.params as { '*': string })['*'];
    const q = req.query as { exp?: string; sig?: string };
    if (!storage.verify(key, Number(q.exp), q.sig ?? '')) {
      throw new AppError(403, 'MEDIA_FORBIDDEN', '사진 주소가 만료됐어요.');
    }
    try {
      const body = await storage.read(key);
      return reply
        .header('content-type', 'image/webp')
        .header('cache-control', 'private, max-age=600')
        .send(body);
    } catch {
      throw new AppError(404, 'NOT_FOUND', '찾을 수 없어요.');
    }
  });
};
