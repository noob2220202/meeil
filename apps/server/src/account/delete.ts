// 탈퇴 (SPEC 8): 보낸 편지·사진·두루마리 글을 지운다. 신고에 묶인 것은 증거로 30일 보관 후 지운다.
// 사용자 행은 개인정보를 모두 비운 "탈퇴" 표시로만 남긴다(다른 사람의 받은 편지·신고 기록의 참조 유지).
import type { Db } from '../db.js';
import type { Storage } from '../storage/storage.js';

const DAY = 24 * 60 * 60 * 1000;
export const DELETED_EVIDENCE_DAYS = 30;
export const DELETED_NAME = '탈퇴한 사용자';

export class AccountService {
  constructor(
    private readonly db: Db,
    private readonly storage: Storage,
    private readonly now: () => Date,
  ) {}

  async deleteAccount(userId: string): Promise<void> {
    const now = this.now();
    const keys: string[] = [];
    await this.db.$transaction(async (tx) => {
      const user = await tx.user.findUnique({ where: { id: userId } });
      if (!user || user.status === 'DELETED') return;

      // 보낸 편지: 신고된 것은 받는 사람에게서 숨기고 보관, 나머지는 사진과 함께 삭제
      const sent = await tx.letter.findMany({
        where: { senderId: userId },
        select: {
          id: true,
          photo: { select: { storageKey: true } },
          _count: { select: { reports: true } },
        },
      });
      const keep = sent.filter((l) => l._count.reports > 0).map((l) => l.id);
      const drop = sent.filter((l) => l._count.reports === 0);
      if (keep.length > 0) {
        await tx.letter.updateMany({
          where: { id: { in: keep } },
          data: { hiddenForRecipient: true, senderPurgedAt: now },
        });
      }
      for (const l of drop) if (l.photo) keys.push(l.photo.storageKey);
      await tx.letter.updateMany({
        where: { replyToId: { in: drop.map((l) => l.id) } },
        data: { replyToId: null },
      });
      await tx.letter.deleteMany({ where: { id: { in: drop.map((l) => l.id) } } });

      // 받은 편지: 내 편지함에서만 지운다(보낸 사람 쪽 기록은 남는다)
      await tx.letter.updateMany({
        where: { recipientId: userId },
        data: { recipientPurgedAt: now },
      });

      // 붙이지 않은 사진
      const orphans = await tx.letterPhoto.findMany({
        where: { uploaderId: userId, letterId: null },
      });
      for (const p of orphans) keys.push(p.storageKey);
      await tx.letterPhoto.deleteMany({ where: { uploaderId: userId, letterId: null } });

      // 두루마리 글: 신고된 것만 보관
      await tx.rollingEntry.deleteMany({ where: { authorId: userId, reports: { none: {} } } });

      // 로그인·기기·활동 기록
      await tx.authIdentity.deleteMany({ where: { userId } });
      await tx.refreshToken.deleteMany({ where: { userId } });
      await tx.fcmToken.deleteMany({ where: { userId } });
      await tx.block.deleteMany({ where: { OR: [{ blockerId: userId }, { blockedId: userId }] } });
      await tx.regionVisit.deleteMany({ where: { userId } });
      await tx.userRegionReport.deleteMany({ where: { userId } });
      await tx.attendance.deleteMany({ where: { userId } });
      await tx.userAchievement.deleteMany({ where: { userId } });
      await tx.userStationery.deleteMany({ where: { userId } });
      await tx.pointsLedger.deleteMany({ where: { userId } });

      await tx.user.update({
        where: { id: userId },
        data: {
          status: 'DELETED',
          deletedAt: now,
          nickname: null,
          nicknameKey: null,
          birthDate: null,
          homeRegionCode: null,
          lastRegionCode: null,
          lastRegionReportedAt: null,
          titleAchievementId: null,
          pointsBalance: 0,
          randomReceive: false,
          notifyEnabled: false,
        },
      });
    });
    for (const k of keys) await this.storage.delete(k).catch(() => undefined);
  }

  /** 탈퇴 30일 뒤 보관하던 신고 증거도 지운다(매일 정리 작업) */
  async purgeDeleted(): Promise<number> {
    const cutoff = new Date(this.now().getTime() - DELETED_EVIDENCE_DAYS * DAY);
    const users = await this.db.user.findMany({
      where: { status: 'DELETED', deletedAt: { lt: cutoff } },
      select: { id: true },
      take: 200,
    });
    let n = 0;
    for (const { id } of users) {
      const letters = await this.db.letter.findMany({
        where: { senderId: id },
        include: { photo: true },
      });
      for (const l of letters) {
        if (l.photo) await this.storage.delete(l.photo.storageKey).catch(() => undefined);
      }
      await this.db.letter.updateMany({
        where: { replyToId: { in: letters.map((l) => l.id) } },
        data: { replyToId: null },
      });
      n += (await this.db.letter.deleteMany({ where: { senderId: id } })).count;
      n += (await this.db.rollingEntry.deleteMany({ where: { authorId: id } })).count;
    }
    return n;
  }
}
