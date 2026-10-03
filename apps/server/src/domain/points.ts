import type { Db } from '../db.js';
import { AppError } from '../errors.js';
import type { LedgerReason } from '../generated/prisma/client.js';

type Tx = Parameters<Parameters<Db['$transaction']>[0]>[0];

/** SPEC 7.1 포인트 수치 [제안] */
export const POINTS = {
  SIGNUP_BONUS: 5,
} as const;

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
    },
  });
  return { applied: true, balanceAfter: user.pointsBalance };
}
