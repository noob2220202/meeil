// 사진 처리 (SPEC 5.1): EXIF 제거, 긴 변 1280px, WebP, 500KB 이내.
import sharp, { type Metadata } from 'sharp';
import { AppError } from '../errors.js';

export const MAX_UPLOAD_BYTES = 10 * 1024 * 1024;
export const MAX_SIDE = 1280;
export const MAX_OUTPUT_BYTES = 500 * 1024;
const ACCEPTED = new Set(['jpeg', 'png', 'webp', 'heif', 'gif']);

export interface ProcessedPhoto {
  webp: Buffer;
  width: number;
  height: number;
  bytes: number;
}

/**
 * 원본을 다시 인코딩한다. sharp는 metadata를 명시적으로 유지하지 않는 한 EXIF·GPS·ICC를 버린다.
 * 방향 정보는 rotate()로 픽셀에 반영한 뒤 버린다.
 */
export async function processPhoto(input: Buffer): Promise<ProcessedPhoto> {
  let meta: Metadata;
  try {
    meta = await sharp(input, { limitInputPixels: 60_000_000 }).metadata();
  } catch {
    throw new AppError(400, 'PHOTO_INVALID', '사진을 읽을 수 없어요. 다른 사진을 골라 주세요.');
  }
  if (!meta.format || !ACCEPTED.has(meta.format)) {
    throw new AppError(400, 'PHOTO_FORMAT', 'JPG, PNG, WEBP, HEIC 사진만 보낼 수 있어요.');
  }
  for (const quality of [82, 74, 66, 58, 50]) {
    const { data, info } = await sharp(input, { limitInputPixels: 60_000_000, animated: false })
      .rotate()
      .resize({ width: MAX_SIDE, height: MAX_SIDE, fit: 'inside', withoutEnlargement: true })
      .webp({ quality, effort: 4 })
      .toBuffer({ resolveWithObject: true });
    if (data.length <= MAX_OUTPUT_BYTES || quality === 50) {
      if (data.length > MAX_OUTPUT_BYTES) {
        throw new AppError(
          400,
          'PHOTO_TOO_COMPLEX',
          '사진이 너무 복잡해요. 다른 사진을 골라 주세요.',
        );
      }
      return { webp: data, width: info.width, height: info.height, bytes: data.length };
    }
  }
  throw new Error('unreachable');
}

/**
 * 자동 검수 훅(SPEC 9.2). 1차에는 비활성 — 항상 통과시키고, 관리자가 사후 검수 피드에서 확인한다.
 * 나중에 NSFW 분류기를 붙일 자리.
 */
export type PhotoModerator = (webp: Buffer) => Promise<'ok' | 'reject'>;
export const noopModerator: PhotoModerator = async () => 'ok';
