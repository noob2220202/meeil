import type { Db } from '../db.js';
import { AppError } from '../errors.js';
import type { LedgerReason } from '../generated/prisma/client.js';

export type Tx = Parameters<Parameters<Db['$transaction']>[0]>[0];

/** SPEC 7.1 포인트 수치 [제안] */
export const POINTS = {
  SIGNUP_BONUS: 5,
  /** 출석 하루 */
  ATTENDANCE: 3,
  /** 7일 연속 출석을 채울 때마다 추가 */
  ATTENDANCE_STREAK_BONUS: 5,
  STREAK_DAYS: 7,
  /** 보상형 광고 1회 */
  AD_REWARD: 2,
  AD_DAILY_MAX: 5,
} as const;

/** 같은 사용자의 포인트 작업을 한 줄로 세운다(하루 상한 같은 검사를 경쟁 없이) */
export async function lockUser(tx: Tx, userId: string): Promise<void> {
  await tx.$executeRaw`SELECT pg_advisory_xact_lock(hashtext(${userId}))`;
}

/**
 * 원장에 한 줄 기록하고 잔액 캐시를 갱신한다. idempotencyKey가 이미 있으면 아무것도 하지 않고
 * 기존 기록을 돌려준다(중복 지급 방지). 잔액이 음수가 되면 INSUFFICIENT_POINTS.
 */
export async function applyLedger(
  tx: Tx,
  entry: {
    userId: string;
    delta: number;
    reason: LedgerReason;
    idempotencyKey: string;
    refId?: string;
    /** 기록 시각(테스트 시계와 맞추기 위해 서비스의 now를 넘긴다) */
    at?: Date;
  },
): Promise<{ applied: boolean; balanceAfter: number }> {
  const existing = await tx.pointsLedger.findUnique({
    where: { idempotencyKey: entry.idempotencyKey },
  });
  if (existing) return { applied: false, balanceAfter: existing.balanceAfter };

  const user = await tx.user.update({
    where: { id: entry.userId },
    data: { pointsBalance: { increment: entry.delta } },
    select: { pointsBalance: true },
  });
  if (user.pointsBalance < 0) {
    throw new AppError(409, 'INSUFFICIENT_POINTS', '포인트가 부족해요.');
  }
  await tx.pointsLedger.create({
    data: {
      userId: entry.userId,
      delta: entry.delta,
      balanceAfter: user.pointsBalance,
      reason: entry.reason,
      idempotencyKey: entry.idempotencyKey,
      refId: entry.refId ?? null,
      createdAt: entry.at ?? new Date(),
    },
  });
  return { applied: true, balanceAfter: user.pointsBalance };
}
