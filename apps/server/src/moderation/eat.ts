// 염소가 편지를 먹어버리는 이벤트 (SPEC 9.3)
import type { Db } from '../db.js';
import { iGa } from '../domain/korean.js';
import { AppError } from '../errors.js';
import type { Pusher } from '../push/push.js';
import type { Storage } from '../storage/storage.js';

const DAY = 24 * 60 * 60 * 1000;
/** 먹힌 원본(본문·사진)을 증거로 남겨 두는 기간 */
export const EVIDENCE_KEEP_DAYS = 30;

export class EatService {
  constructor(
    private readonly db: Db,
    private readonly storage: Storage,
    private readonly pusher: Pusher,
    private readonly now: () => Date,
  ) {}

  /**
   * 관리자 삭제 = 염소가 먹기. 배달 전이면 받는 사람에게 가지 않고, 이미 도착했으면
   * 보관함에서 "염소가 먹어버린 편지"로 바뀐다. 보낸 사람에게 알린다. 여러 번 눌러도 한 번만.
   */
  async eatLetter(letterId: string, reason: string) {
    const l = await this.db.letter.findUnique({
      where: { id: letterId },
      include: { goat: { select: { name: true } }, recipient: { select: { nickname: true } } },
    });
    if (!l) throw new AppError(404, 'LETTER_NOT_FOUND', '편지를 찾을 수 없어요.');
    if (l.status === 'EATEN') return { eaten: false, wasDelivered: l.deliveredAt !== null };
    const { count } = await this.db.letter.updateMany({
      where: { id: letterId, status: { not: 'EATEN' } },
      data: { status: 'EATEN', eatenAt: this.now(), eatenReason: reason },
    });
    if (count === 0) return { eaten: false, wasDelivered: l.deliveredAt !== null };
    await this.resolveReports({ letterId });
    const goat = l.goat?.name ?? '우체부 염소';
    await this.pusher
      .sendToUser(l.senderId, {
        title: '염소가 편지를 먹어버렸어요',
        body: `${iGa(goat)} ${l.recipient.nickname ?? '받는 사람'}님에게 가던 편지를 먹어버렸어요. (부적절한 내용)`,
        data: { type: 'letter-eaten', letterId },
      })
      .catch(() => 0);
    return { eaten: true, wasDelivered: l.deliveredAt !== null };
  }

  /** 롤링페이퍼 글 먹기: 두루마리에서 그 글이 먹히는 연출 */
  async eatRollingEntry(entryId: string) {
    const e = await this.db.rollingEntry.findUnique({ where: { id: entryId } });
    if (!e) throw new AppError(404, 'ENTRY_NOT_FOUND', '글을 찾을 수 없어요.');
    if (e.status === 'EATEN') return { eaten: false };
    await this.db.rollingEntry.update({
      where: { id: entryId },
      data: { status: 'EATEN', eatenAt: this.now() },
    });
    await this.resolveReports({ rollingEntryId: entryId });
    await this.pusher
      .sendToUser(e.authorId, {
        title: '염소가 두루마리 글을 먹어버렸어요',
        body: '부적절한 내용이라 두루마리 염소가 냠냠 먹어버렸어요.',
        data: { type: 'rolling-eaten', paperId: e.paperId },
      })
      .catch(() => 0);
    return { eaten: true };
  }

  private async resolveReports(where: { letterId?: string; rollingEntryId?: string }) {
    await this.db.report.updateMany({
      where: { ...where, status: 'OPEN' },
      data: { status: 'RESOLVED', resolvedAt: this.now() },
    });
  }

  /** 증거 보존 기간이 지난 먹힌 원본 지우기(매일 정리 작업) */
  async purgeEvidence(): Promise<number> {
    const cutoff = new Date(this.now().getTime() - EVIDENCE_KEEP_DAYS * DAY);
    const letters = await this.db.letter.findMany({
      where: { status: 'EATEN', eatenAt: { lt: cutoff }, NOT: { body: '' } },
      include: { photo: true },
      take: 500,
    });
    for (const l of letters) {
      if (l.photo) {
        await this.storage.delete(l.photo.storageKey).catch(() => undefined);
        await this.db.letterPhoto.delete({ where: { id: l.photo.id } });
      }
      await this.db.letter.update({ where: { id: l.id }, data: { body: '', stickers: [] } });
    }
    const entries = await this.db.rollingEntry.updateMany({
      where: { status: 'EATEN', eatenAt: { lt: cutoff }, NOT: { body: '' } },
      data: { body: '', stickers: [] },
    });
    return letters.length + entries.count;
  }
}
