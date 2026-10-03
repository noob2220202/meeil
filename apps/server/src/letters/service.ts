// 편지 맡기기·배달·보관함 (SPEC 3, 5)
import type { Db } from '../db.js';
import { iGa } from '../domain/korean.js';
import { applyLedger } from '../domain/points.js';
import { AppError } from '../errors.js';
import type { LetterMode, Prisma, RandomScope } from '../generated/prisma/client.js';
import type { Pusher } from '../push/push.js';
import { HARD_CAP_MS, MIN_TRANSIT_MS } from '../schedule/eta.js';
import type { Storage } from '../storage/storage.js';
import { deliveryGoatsStayingAt } from './presence.js';
import {
  DAILY_SEND_LIMIT,
  LETTER_COST,
  RANDOM_RECENT_DAYS,
  REGION_FRESH_MS,
  TRASH_KEEP_DAYS,
  kstDayRange,
  type PlacedSticker,
} from './rules.js';

const DAY = 24 * 60 * 60 * 1000;

export interface HandInput {
  mode: LetterMode;
  recipientId?: string;
  replyToId?: string;
  randomScope?: RandomScope;
  body: string;
  stationeryId: string;
  stickers: PlacedSticker[];
  photoId?: string;
  clientRequestId: string;
}

export type Box = 'inbox' | 'sent' | 'trash';

const letterInclude = {
  sender: {
    select: { id: true, nickname: true, titleAchievement: { select: { titleText: true } } },
  },
  recipient: { select: { id: true, nickname: true } },
  goat: { select: { id: true, name: true, hatColor: true, bagColor: true } },
  photo: { select: { storageKey: true, width: true, height: true } },
} satisfies Prisma.LetterInclude;

type LetterRow = Prisma.LetterGetPayload<{ include: typeof letterInclude }>;

export class LetterService {
  constructor(
    private readonly db: Db,
    private readonly storage: Storage,
    private readonly pusher: Pusher,
    private readonly now: () => Date,
  ) {}

  // ───────── 맡기기 ─────────

  async hand(senderId: string, input: HandInput) {
    const now = this.now();

    // 같은 요청 재전송이면 이미 맡긴 편지를 그대로 돌려준다
    const dup = await this.db.letter.findUnique({
      where: { senderId_clientRequestId: { senderId, clientRequestId: input.clientRequestId } },
      include: letterInclude,
    });
    if (dup) return this.dto(dup, senderId);

    const sender = await this.db.user.findUniqueOrThrow({ where: { id: senderId } });
    if (!sender.nickname || !sender.birthDate || !sender.termsAgreedAt) {
      throw new AppError(403, 'ONBOARDING_REQUIRED', '가입을 마친 뒤에 편지를 보낼 수 있어요.');
    }
    if (sender.status === 'SUSPENDED' && sender.suspendedUntil && sender.suspendedUntil > now) {
      throw new AppError(403, 'SUSPENDED', '이용이 잠시 정지된 계정이에요.');
    }

    // 염소가 내 시에 있어야 맡길 수 있다(SPEC 3.2)
    const origin = sender.lastRegionCode;
    if (
      !origin ||
      !sender.lastRegionReportedAt ||
      now.getTime() - sender.lastRegionReportedAt.getTime() > REGION_FRESH_MS
    ) {
      throw new AppError(
        409,
        'REGION_UNKNOWN',
        '지금 어느 시에 있는지 확인한 뒤에 맡길 수 있어요.',
      );
    }
    const here = await deliveryGoatsStayingAt(this.db, origin, now);
    if (here.length === 0) {
      throw new AppError(
        409,
        'NO_GOAT_HERE',
        '지금은 우리 동네에 배달 염소가 없어요. 염소가 오면 맡겨 주세요.',
      );
    }

    const { start, end } = kstDayRange(now);
    const today = await this.db.letter.count({
      where: { senderId, handedAt: { gte: start, lt: end } },
    });
    if (today >= DAILY_SEND_LIMIT) {
      throw new AppError(
        429,
        'DAILY_LIMIT',
        `편지는 하루에 ${DAILY_SEND_LIMIT}통까지 보낼 수 있어요.`,
      );
    }

    const owns = await this.db.userStationery.findUnique({
      where: { userId_stationeryId: { userId: senderId, stationeryId: input.stationeryId } },
    });
    if (!owns) throw new AppError(400, 'STATIONERY_LOCKED', '아직 열리지 않은 편지지예요.');

    const recipient = await this.resolveRecipient(sender.id, origin, input);
    const dest = recipient.lastRegionCode ?? recipient.homeRegionCode ?? origin;
    const hidden = Boolean(
      await this.db.block.findUnique({
        where: { blockerId_blockedId: { blockerId: recipient.id, blockedId: senderId } },
      }),
    );
    const eta = await this.eta(dest, now);

    const created = await this.db.$transaction(async (tx) => {
      const letter = await tx.letter.create({
        data: {
          mode: input.mode,
          senderId,
          recipientId: recipient.id,
          replyToId: input.mode === 'REPLY' ? input.replyToId : null,
          randomScope: input.mode === 'RANDOM' ? input.randomScope : null,
          randomScopeCode: input.mode === 'RANDOM' ? scopeCode(input.randomScope!, origin) : null,
          originRegionCode: origin,
          destRegionCode: dest,
          body: input.body,
          stationeryId: input.stationeryId,
          stickers: input.stickers as unknown as Prisma.InputJsonValue,
          // 배정 염소·도착 시각이 바로 정해지므로 맡기는 즉시 이동 중(HANDED는 순간 상태)
          status: 'IN_TRANSIT',
          handedAt: now,
          etaAt: new Date(eta.arriveAt),
          goatId: eta.goatId,
          pickupGoatId: here[0]!.id,
          express: eta.express,
          hiddenForRecipient: hidden,
          clientRequestId: input.clientRequestId,
        },
      });
      await applyLedger(tx, {
        userId: senderId,
        delta: -LETTER_COST,
        reason: 'LETTER_SEND',
        idempotencyKey: `letter:${letter.id}`,
        refId: letter.id,
      });
      if (input.photoId) {
        const { count } = await tx.letterPhoto.updateMany({
          where: { id: input.photoId, uploaderId: senderId, letterId: null },
          data: { letterId: letter.id },
        });
        if (count === 0) throw new AppError(400, 'PHOTO_NOT_FOUND', '사진을 다시 올려 주세요.');
      }
      return tx.letter.findUniqueOrThrow({ where: { id: letter.id }, include: letterInclude });
    });
    return this.dto(created, senderId);
  }

  private async resolveRecipient(senderId: string, origin: string, input: HandInput) {
    const eligible = {
      status: { in: ['ACTIVE', 'SUSPENDED'] },
      nickname: { not: null },
      birthDate: { not: null },
      termsAgreedAt: { not: null },
    } satisfies Prisma.UserWhereInput;

    if (input.mode === 'DIRECT') {
      if (!input.recipientId) throw new AppError(400, 'VALIDATION', '받는 사람을 골라 주세요.');
      if (input.recipientId === senderId) {
        throw new AppError(400, 'SELF_LETTER', '나에게는 편지를 보낼 수 없어요.');
      }
      const r = await this.db.user.findFirst({ where: { id: input.recipientId, ...eligible } });
      if (!r) throw new AppError(404, 'RECIPIENT_NOT_FOUND', '받는 사람을 찾을 수 없어요.');
      return r;
    }

    if (input.mode === 'REPLY') {
      const original = await this.db.letter.findFirst({
        where: {
          id: input.replyToId,
          recipientId: senderId,
          status: { in: ['DELIVERED', 'READ'] },
        },
      });
      if (!original) throw new AppError(404, 'LETTER_NOT_FOUND', '답장할 편지를 찾을 수 없어요.');
      const r = await this.db.user.findFirst({ where: { id: original.senderId, ...eligible } });
      if (!r)
        throw new AppError(
          404,
          'RECIPIENT_NOT_FOUND',
          '이 편지를 보낸 사람이 더 이상 메에일에 없어요.',
        );
      return r;
    }

    // RANDOM: 범위 안의 랜덤 수신 ON 사용자, 차단 관계 제외, 최근 7일 접속자 우선(SPEC 5.2)
    const scope = input.randomScope ?? 'NATION';
    const originRegion = await this.db.region.findUniqueOrThrow({ where: { code: origin } });
    const regionFilter: Prisma.UserWhereInput =
      scope === 'CITY'
        ? { lastRegionCode: origin }
        : scope === 'PROVINCE'
          ? { lastRegion: { provinceCode: originRegion.provinceCode } }
          : {};
    const base: Prisma.UserWhereInput = {
      ...eligible,
      ...regionFilter,
      id: { not: senderId },
      randomReceive: true,
      blocking: { none: { blockedId: senderId } },
      blockedBy: { none: { blockerId: senderId } },
    };
    const recentSince = new Date(this.now().getTime() - RANDOM_RECENT_DAYS * DAY);
    for (const where of [{ ...base, lastActiveAt: { gte: recentSince } }, base]) {
      const count = await this.db.user.count({ where });
      if (count === 0) continue;
      const skip = Math.floor(Math.random() * count);
      const r = await this.db.user.findFirst({ where, skip, orderBy: { id: 'asc' } });
      if (r) return r;
    }
    const wider = scope === 'CITY' ? '도나 전국' : scope === 'PROVINCE' ? '전국' : null;
    throw new AppError(
      409,
      'NO_RANDOM_RECIPIENT',
      wider
        ? `이 범위에는 랜덤 편지를 받을 사람이 아직 없어요. ${wider}으로 넓혀 보세요.`
        : '지금은 랜덤 편지를 받을 사람이 없어요. 조금 뒤에 다시 시도해 주세요.',
    );
  }

  /** 맡긴 뒤 1시간 이후 목적지에 처음 도착하는 배달 염소. 72시간 안에 없으면 특급 배달 */
  private async eta(dest: string, handedAt: Date) {
    const earliest = new Date(handedAt.getTime() + MIN_TRANSIT_MS);
    const cap = new Date(handedAt.getTime() + HARD_CAP_MS);
    const next = await this.db.goatScheduleStop.findFirst({
      where: {
        regionCode: dest,
        arriveAt: { gte: earliest, lte: cap },
        goat: { kind: 'DELIVERY', active: true },
      },
      orderBy: { arriveAt: 'asc' },
    });
    if (next) return { arriveAt: next.arriveAt.getTime(), goatId: next.goatId, express: false };
    const fastest = await this.db.goat.findFirstOrThrow({
      where: { kind: 'DELIVERY', active: true },
      orderBy: { speedKmh: 'desc' },
    });
    return { arriveAt: cap.getTime(), goatId: fastest.id, express: true };
  }

  // ───────── 배달 ─────────

  /** 도착 시각이 지난 편지를 받은 편지함에 넣고 알린다. 몇 통 배달했는지 돌려준다. */
  async deliverDue(): Promise<number> {
    const now = this.now();
    const due = await this.db.letter.findMany({
      where: { status: 'IN_TRANSIT', etaAt: { lte: now } },
      include: { sender: { select: { nickname: true } }, goat: { select: { name: true } } },
      orderBy: { etaAt: 'asc' },
      take: 500,
    });
    let delivered = 0;
    for (const l of due) {
      // 동시에 도는 작업이 있어도 한 번만 배달되게
      const { count } = await this.db.letter.updateMany({
        where: { id: l.id, status: 'IN_TRANSIT' },
        data: { status: 'DELIVERED', deliveredAt: l.etaAt },
      });
      if (count === 0) continue;
      delivered++;
      if (l.hiddenForRecipient) continue;
      const recipient = await this.db.user.findUnique({
        where: { id: l.recipientId },
        select: { notifyEnabled: true },
      });
      if (!recipient?.notifyEnabled) continue;
      await this.pusher
        .sendToUser(l.recipientId, {
          title: '편지가 도착했어요',
          body: `${iGa(l.goat?.name ?? '우체부 염소')} ${l.sender.nickname ?? '누군가'}님의 편지를 가져왔어요.`,
          data: { type: 'letter', letterId: l.id },
        })
        .catch(() => 0);
    }
    return delivered;
  }

  // ───────── 보관함 ─────────

  async list(userId: string, box: Box, cursor?: string, limit = 30) {
    // 조회할 때 밀린 배달을 먼저 처리해 화면이 늘 최신이 되게 한다
    await this.deliverDue();
    const where: Prisma.LetterWhereInput =
      box === 'inbox'
        ? {
            recipientId: userId,
            status: { in: ['DELIVERED', 'READ', 'EATEN'] },
            deliveredAt: { not: null },
            recipientTrashedAt: null,
            hiddenForRecipient: false,
          }
        : box === 'sent'
          ? { senderId: userId, senderTrashedAt: null }
          : {
              OR: [
                { senderId: userId, senderTrashedAt: { not: null }, senderPurgedAt: null },
                {
                  recipientId: userId,
                  recipientTrashedAt: { not: null },
                  recipientPurgedAt: null,
                  hiddenForRecipient: false,
                },
              ],
            };
    const rows = await this.db.letter.findMany({
      where,
      include: letterInclude,
      orderBy:
        box === 'inbox'
          ? [{ deliveredAt: 'desc' }, { id: 'desc' }]
          : [{ handedAt: 'desc' }, { id: 'desc' }],
      take: limit + 1,
      ...(cursor ? { cursor: { id: cursor }, skip: 1 } : {}),
    });
    const page = rows.slice(0, limit);
    return {
      letters: await Promise.all(page.map((l) => this.dto(l, userId))),
      nextCursor: rows.length > limit ? page[page.length - 1]!.id : null,
    };
  }

  async unreadCount(userId: string): Promise<number> {
    await this.deliverDue();
    return this.db.letter.count({
      where: {
        recipientId: userId,
        status: 'DELIVERED',
        recipientTrashedAt: null,
        hiddenForRecipient: false,
      },
    });
  }

  /** 볼 권한이 있는 편지 하나 */
  private async findVisible(userId: string, id: string): Promise<LetterRow> {
    await this.deliverDue();
    const l = await this.db.letter.findUnique({ where: { id }, include: letterInclude });
    const asSender = l && l.senderId === userId && !l.senderPurgedAt;
    const asRecipient =
      l &&
      l.recipientId === userId &&
      !l.recipientPurgedAt &&
      !l.hiddenForRecipient &&
      l.deliveredAt !== null;
    if (!l || (!asSender && !asRecipient)) {
      throw new AppError(404, 'LETTER_NOT_FOUND', '편지를 찾을 수 없어요.');
    }
    return l;
  }

  async get(userId: string, id: string) {
    return this.dto(await this.findVisible(userId, id), userId);
  }

  async markRead(userId: string, id: string) {
    const l = await this.findVisible(userId, id);
    if (l.recipientId === userId && l.status === 'DELIVERED') {
      await this.db.letter.update({ where: { id }, data: { status: 'READ', readAt: this.now() } });
    }
    return this.get(userId, id);
  }

  async trash(userId: string, id: string) {
    const l = await this.findVisible(userId, id);
    const now = this.now();
    await this.db.letter.update({
      where: { id },
      data: l.senderId === userId ? { senderTrashedAt: now } : { recipientTrashedAt: now },
    });
    return this.get(userId, id);
  }

  async restore(userId: string, id: string) {
    const l = await this.findVisible(userId, id);
    await this.db.letter.update({
      where: { id },
      data: l.senderId === userId ? { senderTrashedAt: null } : { recipientTrashedAt: null },
    });
    return this.get(userId, id);
  }

  /** 휴지통에서 영구 삭제(내 쪽만 지운다. 상대 복사본은 유지 — SPEC 5.4) */
  async purge(userId: string, id: string) {
    const l = await this.findVisible(userId, id);
    const mine = l.senderId === userId ? l.senderTrashedAt : l.recipientTrashedAt;
    if (!mine) throw new AppError(409, 'NOT_IN_TRASH', '휴지통에 있는 편지만 지울 수 있어요.');
    const now = this.now();
    await this.db.letter.update({
      where: { id },
      data: l.senderId === userId ? { senderPurgedAt: now } : { recipientPurgedAt: now },
    });
    await this.deleteIfOrphan(id);
  }

  /** 휴지통 30일 경과분 영구 삭제 + 양쪽 다 지운 편지는 실제로 삭제 */
  async purgeExpiredTrash(): Promise<number> {
    const cutoff = new Date(this.now().getTime() - TRASH_KEEP_DAYS * DAY);
    const now = this.now();
    const a = await this.db.letter.updateMany({
      where: { senderTrashedAt: { lt: cutoff }, senderPurgedAt: null },
      data: { senderPurgedAt: now },
    });
    const b = await this.db.letter.updateMany({
      where: { recipientTrashedAt: { lt: cutoff }, recipientPurgedAt: null },
      data: { recipientPurgedAt: now },
    });
    const both = await this.db.letter.findMany({
      where: { senderPurgedAt: { not: null }, recipientPurgedAt: { not: null } },
      select: { id: true },
    });
    for (const { id } of both) await this.deleteIfOrphan(id);
    return a.count + b.count;
  }

  /** 발신·수신 양쪽에서 지워졌고 신고 증거로 묶여 있지 않으면 사진과 함께 지운다 */
  private async deleteIfOrphan(id: string) {
    const l = await this.db.letter.findUnique({
      where: { id },
      include: { photo: true, _count: { select: { reports: true, replies: true } } },
    });
    if (!l || !l.senderPurgedAt || !l.recipientPurgedAt || l._count.reports > 0) return;
    if (l.photo) await this.storage.delete(l.photo.storageKey).catch(() => undefined);
    await this.db.letter.delete({ where: { id } });
  }

  // ───────── 응답 형태 ─────────

  /**
   * 보는 사람 관점의 편지. 소셜 ID·생년월일 등은 포함하지 않는다.
   * 랜덤 편지의 받는 사람은 도착 전까지 발신자에게 감춘다.
   */
  async dto(l: LetterRow, viewerId: string) {
    const isSender = l.senderId === viewerId;
    const eaten = l.status === 'EATEN';
    const delivered = l.deliveredAt !== null;
    const photo =
      l.photo && !eaten
        ? {
            url: await this.storage.signedUrl(l.photo.storageKey),
            width: l.photo.width,
            height: l.photo.height,
            // 랜덤 편지 사진은 받는 쪽에서 기본 블러(SPEC 5.2)
            blurred: l.mode === 'RANDOM' && !isSender,
          }
        : null;
    return {
      id: l.id,
      mode: l.mode,
      role: isSender ? ('sender' as const) : ('recipient' as const),
      status: l.status,
      sender: {
        id: l.sender.id,
        nickname: l.sender.nickname,
        title: l.sender.titleAchievement?.titleText ?? null,
      },
      recipient:
        isSender && l.mode === 'RANDOM' && !delivered
          ? null
          : { id: l.recipient.id, nickname: l.recipient.nickname },
      body: eaten ? null : l.body,
      stationeryId: l.stationeryId,
      stickers: eaten ? [] : (l.stickers as unknown as PlacedSticker[]),
      photo,
      randomScope: l.randomScope,
      originRegionCode: l.originRegionCode,
      destRegionCode: isSender ? l.destRegionCode : null,
      goat: l.goat
        ? { id: l.goat.id, name: l.goat.name, hatColor: l.goat.hatColor, bagColor: l.goat.bagColor }
        : null,
      pickupGoatId: l.pickupGoatId,
      express: l.express,
      handedAt: l.handedAt.toISOString(),
      etaAt: l.etaAt?.toISOString() ?? null,
      deliveredAt: l.deliveredAt?.toISOString() ?? null,
      readAt: l.readAt?.toISOString() ?? null,
      eatenAt: l.eatenAt?.toISOString() ?? null,
      replyToId: l.replyToId,
      trashedAt: (isSender ? l.senderTrashedAt : l.recipientTrashedAt)?.toISOString() ?? null,
      canReply: !isSender && (l.status === 'DELIVERED' || l.status === 'READ'),
    };
  }
}

export type LetterDto = Awaited<ReturnType<LetterService['dto']>>;

function scopeCode(scope: RandomScope, origin: string): string {
  return scope === 'CITY' ? origin : scope === 'PROVINCE' ? origin.slice(0, 2) : 'KR';
}
