// 신고 (SPEC 9.1)
import type { Db } from '../db.js';
import { AppError } from '../errors.js';
import type { ReportTargetType } from '../generated/prisma/client.js';
import { kstDayRange } from '../letters/rules.js';

export const REPORT_REASONS = {
  SPAM: '도배·광고',
  ABUSE: '욕설·괴롭힘',
  SEXUAL: '성적인 내용',
  PERSONAL_INFO: '개인정보 노출',
  DANGER: '위험하거나 불법적인 내용',
  OTHER: '기타',
} as const;
export type ReportReason = keyof typeof REPORT_REASONS;

export const REPORTS_PER_DAY = 20;

export class ReportService {
  constructor(
    private readonly db: Db,
    private readonly now: () => Date,
  ) {}

  /** 신고 대상이 나에게 보이는지 확인하고 피신고자를 정한다 */
  private async resolveTarget(reporterId: string, type: ReportTargetType, targetId: string) {
    if (type === 'LETTER') {
      const l = await this.db.letter.findUnique({ where: { id: targetId } });
      const asRecipient =
        l && l.recipientId === reporterId && l.deliveredAt !== null && !l.hiddenForRecipient;
      const asSender = l && l.senderId === reporterId;
      if (!l || (!asRecipient && !asSender)) {
        throw new AppError(404, 'TARGET_NOT_FOUND', '신고할 편지를 찾을 수 없어요.');
      }
      return { letterId: l.id, targetUserId: asRecipient ? l.senderId : l.recipientId };
    }
    if (type === 'ROLLING_ENTRY') {
      const e = await this.db.rollingEntry.findUnique({ where: { id: targetId } });
      if (!e) throw new AppError(404, 'TARGET_NOT_FOUND', '신고할 글을 찾을 수 없어요.');
      if (e.authorId === reporterId) {
        throw new AppError(400, 'SELF_REPORT', '내 글은 신고할 수 없어요.');
      }
      return { rollingEntryId: e.id, targetUserId: e.authorId };
    }
    if (targetId === reporterId) throw new AppError(400, 'SELF_REPORT', '나를 신고할 수는 없어요.');
    const u = await this.db.user.findUnique({ where: { id: targetId }, select: { id: true } });
    if (!u) throw new AppError(404, 'TARGET_NOT_FOUND', '신고할 사용자를 찾을 수 없어요.');
    return { targetUserId: u.id };
  }

  async create(
    reporterId: string,
    input: {
      targetType: ReportTargetType;
      targetId: string;
      reason: ReportReason;
      detail?: string;
    },
  ) {
    const target = await this.resolveTarget(reporterId, input.targetType, input.targetId);
    // 같은 대상을 이미 신고해 처리 대기 중이면 그대로 돌려준다
    const dup = await this.db.report.findFirst({
      where: {
        reporterId,
        targetType: input.targetType,
        status: 'OPEN',
        ...(input.targetType === 'LETTER'
          ? { letterId: target.letterId }
          : input.targetType === 'ROLLING_ENTRY'
            ? { rollingEntryId: target.rollingEntryId }
            : { targetUserId: target.targetUserId }),
      },
    });
    if (dup) return { id: dup.id, duplicate: true };
    const { start, end } = kstDayRange(this.now());
    const today = await this.db.report.count({
      where: { reporterId, createdAt: { gte: start, lt: end } },
    });
    if (today >= REPORTS_PER_DAY) {
      throw new AppError(
        429,
        'REPORT_LIMIT',
        '오늘은 신고를 더 할 수 없어요. 내일 다시 해 주세요.',
      );
    }
    const r = await this.db.report.create({
      data: {
        reporterId,
        targetType: input.targetType,
        reason: input.reason,
        detail: input.detail ?? null,
        createdAt: this.now(),
        ...target,
      },
    });
    return { id: r.id, duplicate: false };
  }
}
