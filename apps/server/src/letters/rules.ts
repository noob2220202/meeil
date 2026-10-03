// 편지 규칙 (SPEC 5)
import { kstToday } from '../domain/age.js';

export const BODY_MAX = 200;
export const STICKERS_MAX = 3;
export const DAILY_SEND_LIMIT = 20;
export const LETTER_COST = 1;
export const TRASH_KEEP_DAYS = 30;
/** 이 시간 안에 보고한 위치여야 "지금 염소가 내 시에 있다"를 믿는다 */
export const REGION_FRESH_MS = 30 * 60 * 1000;
/** 랜덤 수신 우선 대상: 최근 접속 */
export const RANDOM_RECENT_DAYS = 7;

/** 스티커 20종 (SPEC 12.3). 앱 assets/stickers/<id>.svg 와 같은 이름 */
export const STICKER_IDS = [
  'heart',
  'star',
  'flower',
  'clover',
  'cloud',
  'sun',
  'moon',
  'note',
  'letter',
  'gift',
  'ribbon',
  'rainbow',
  'cherry',
  'leaf',
  'goat-smile',
  'goat-love',
  'goat-sleep',
  'goat-wow',
  'goat-laugh',
  'goat-tear',
] as const;

/** 편지지에 붙인 스티커 하나: 종류와 편지지 위 위치(0~1) */
export interface PlacedSticker {
  id: (typeof STICKER_IDS)[number];
  x: number;
  y: number;
}

/** KST 기준 오늘 00:00 ~ 내일 00:00 (UTC Date) */
export function kstDayRange(now: Date): { start: Date; end: Date } {
  const [y, m, d] = kstToday(now);
  const start = new Date(Date.UTC(y, m - 1, d) - 9 * 60 * 60 * 1000);
  return { start, end: new Date(start.getTime() + 24 * 60 * 60 * 1000) };
}
