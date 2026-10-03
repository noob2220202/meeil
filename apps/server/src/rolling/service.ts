// 롤링페이퍼 (SPEC 6, 4.2)
import { DELETED_NAME } from '../account/delete.js';
import type { Db } from '../db.js';
import { kstToday } from '../domain/age.js';
import { AppError } from '../errors.js';
import type { Prisma, RollingLevel } from '../generated/prisma/client.js';
import { REGION_FRESH_MS, type PlacedSticker } from '../letters/rules.js';
import { METRICS, type AchievementService } from '../rewards/achievements.js';
import { NATION_PERIOD_MS, PROVINCE_PERIOD_MS, SCHEDULE_EPOCH } from '../schedule/timeline.js';

const DAY = 24 * 60 * 60 * 1000;
const KST = 9 * 60 * 60 * 1000;

/** 장 주기(SPEC 4.2): 전국 주 1장(월 00:00 KST~), 도 3일 1장, 시 하루 1장(KST) */
export function periodOf(level: RollingLevel, at: Date): { start: Date; end: Date } {
  const t = at.getTime();
  if (level === 'CITY') {
    const [y, m, d] = kstToday(at);
    const start = Date.UTC(y, m - 1, d) - KST;
    return { start: new Date(start), end: new Date(start + DAY) };
  }
  const len = level === 'NATION' ? NATION_PERIOD_MS : PROVINCE_PERIOD_MS;
  const k = Math.floor((t - SCHEDULE_EPOCH) / len);
  const start = SCHEDULE_EPOCH + k * len;
  return { start: new Date(start), end: new Date(start + len) };
}

/** 지역 코드 → 레벨별 범위 코드 */
export function scopeOf(level: RollingLevel, regionCode: string, provinceCode: string): string {
  return level === 'NATION' ? 'KR' : level === 'PROVINCE' ? provinceCode : regionCode;
}

const entryInclude = {
  author: {
    select: { id: true, nickname: true, titleAchievement: { select: { titleText: true } } },
  },
} satisfies Prisma.RollingEntryInclude;

type EntryRow = Prisma.RollingEntryGetPayload<{ include: typeof entryInclude }>;
type PaperRow = Prisma.RollingPaperGetPayload<object>;

export type JoinBlock =
  'ALREADY_JOINED' | 'REGION_UNKNOWN' | 'NOT_IN_SCOPE' | 'NO_GOAT_HERE' | 'CLOSED';

export class RollingService {
  constructor(
    private readonly db: Db,
    private readonly now: () => Date,
    private readonly achievements?: AchievementService,
  ) {}

  /** 지금 보고된(30분 이내) 내 시. 없으면 null */
  private async myRegion(userId: string) {
    const u = await this.db.user.findUniqueOrThrow({
      where: { id: userId },
      include: { lastRegion: true },
    });
    const fresh =
      u.lastRegion &&
      u.lastRegionReportedAt &&
      this.now().getTime() - u.lastRegionReportedAt.getTime() <= REGION_FRESH_MS;
    return { user: u, region: fresh ? u.lastRegion : null, lastRegion: u.lastRegion };
  }

  private async paperFor(level: RollingLevel, scopeCode: string): Promise<PaperRow> {
    const { start, end } = periodOf(level, this.now());
    return this.db.rollingPaper.upsert({
      where: { level_scopeCode_periodStart: { level, scopeCode, periodStart: start } },
      create: { level, scopeCode, periodStart: start, periodEnd: end },
      update: {},
    });
  }

  /** 이 레벨의 롤링 염소가 지금 [regionCode]에 머무는가. 시 롤링 염소는 늘 있다. */
  private async goatHere(level: RollingLevel, regionCode: string, provinceCode: string) {
    if (level === 'CITY') return { here: true, nextArriveAt: null as Date | null };
    const now = this.now();
    const goat = {
      kind: level === 'NATION' ? ('ROLLING_NATION' as const) : ('ROLLING_PROVINCE' as const),
      active: true,
      ...(level === 'PROVINCE' ? { scopeCode: provinceCode } : {}),
    };
    const staying = await this.db.goatScheduleStop.findFirst({
      where: { regionCode, arriveAt: { lte: now }, departAt: { gt: now }, goat },
    });
    if (staying) return { here: true, nextArriveAt: null };
    const next = await this.db.goatScheduleStop.findFirst({
      where: { regionCode, arriveAt: { gt: now }, goat },
      orderBy: { arriveAt: 'asc' },
    });
    return { here: false, nextArriveAt: next?.arriveAt ?? null };
  }

  /**
   * 레벨별 이번 장. 진행 중인 장은 그 지역 사람만 볼 수 있다(SPEC 6).
   * 전국 장은 위치를 몰라도 볼 수 있다(참여는 위치가 필요).
   */
  async current(userId: string, level: RollingLevel) {
    const { region, lastRegion } = await this.myRegion(userId);
    const area = region ?? lastRegion;
    if (level !== 'NATION' && !area) {
      throw new AppError(409, 'REGION_UNKNOWN', '지금 있는 시를 확인한 뒤에 볼 수 있어요.');
    }
    const scopeCode = area ? scopeOf(level, area.code, area.provinceCode) : 'KR';
    const paper = await this.paperFor(level, scopeCode);
    return this.paperView(userId, paper);
  }

  async get(userId: string, paperId: string) {
    const paper = await this.db.rollingPaper.findUnique({ where: { id: paperId } });
    if (!paper) throw new AppError(404, 'PAPER_NOT_FOUND', '두루마리를 찾을 수 없어요.');
    const closed = paper.periodEnd <= this.now();
    if (closed) {
      // 마감된 장은 참여자만(앨범)
      const mine = await this.db.rollingEntry.findUnique({
        where: { paperId_authorId: { paperId, authorId: userId } },
      });
      if (!mine)
        throw new AppError(403, 'PAPER_CLOSED', '마감된 두루마리는 참여한 사람만 볼 수 있어요.');
    } else if (paper.level !== 'NATION') {
      const { region, lastRegion } = await this.myRegion(userId);
      const area = region ?? lastRegion;
      if (!area || scopeOf(paper.level, area.code, area.provinceCode) !== paper.scopeCode) {
        throw new AppError(403, 'NOT_IN_SCOPE', '이 두루마리는 그 지역에 있을 때만 볼 수 있어요.');
      }
    }
    return this.paperView(userId, paper);
  }

  private async paperView(userId: string, paper: PaperRow) {
    const now = this.now();
    const entries = await this.db.rollingEntry.findMany({
      where: { paperId: paper.id },
      include: entryInclude,
      orderBy: { createdAt: 'asc' },
    });
    const join = await this.joinStatus(userId, paper, entries);
    // 내가 차단한 사람의 글은 보이지 않는다(SPEC 9.1)
    const blocked = new Set(
      (
        await this.db.block.findMany({ where: { blockerId: userId }, select: { blockedId: true } })
      ).map((b) => b.blockedId),
    );
    const visible = entries.filter((e) => !blocked.has(e.authorId));
    return {
      paper: await this.paperDto(paper),
      entries: visible.map((e) => entryDto(e, userId)),
      joined: entries.some((e) => e.authorId === userId),
      canJoin: join.block === null,
      joinBlock: join.block,
      goatHere: join.goatHere,
      goatNextArriveAt: join.nextArriveAt?.toISOString() ?? null,
      closed: paper.periodEnd <= now,
    };
  }

  private async joinStatus(userId: string, paper: PaperRow, entries: EntryRow[]) {
    const now = this.now();
    const result = (
      block: JoinBlock | null,
      goatHere = false,
      nextArriveAt: Date | null = null,
    ) => ({
      block,
      goatHere,
      nextArriveAt,
    });
    if (paper.periodEnd <= now || paper.periodStart > now) return result('CLOSED');
    if (entries.some((e) => e.authorId === userId)) return result('ALREADY_JOINED', true);
    const { region } = await this.myRegion(userId);
    if (!region) return result('REGION_UNKNOWN');
    if (scopeOf(paper.level, region.code, region.provinceCode) !== paper.scopeCode) {
      return result('NOT_IN_SCOPE');
    }
    const g = await this.goatHere(paper.level, region.code, region.provinceCode);
    return result(g.here ? null : 'NO_GOAT_HERE', g.here, g.nextArriveAt);
  }

  private async paperDto(p: PaperRow) {
    let scopeName = '전국';
    if (p.level === 'PROVINCE') {
      scopeName =
        (await this.db.province.findUnique({ where: { code: p.scopeCode } }))?.shortName ??
        p.scopeCode;
    } else if (p.level === 'CITY') {
      scopeName =
        (await this.db.region.findUnique({ where: { code: p.scopeCode } }))?.fullName ??
        p.scopeCode;
    }
    const goat =
      p.level === 'NATION'
        ? await this.db.goat.findFirst({ where: { kind: 'ROLLING_NATION' } })
        : p.level === 'PROVINCE'
          ? await this.db.goat.findFirst({
              where: { kind: 'ROLLING_PROVINCE', scopeCode: p.scopeCode },
            })
          : await this.db.goat.findFirst({
              where: { kind: 'ROLLING_CITY', scopeCode: p.scopeCode },
            });
    return {
      id: p.id,
      level: p.level,
      scopeCode: p.scopeCode,
      scopeName,
      topic: p.topic ?? (await this.topicFor(p)),
      periodStart: p.periodStart.toISOString(),
      periodEnd: p.periodEnd.toISOString(),
      goat: goat
        ? { id: goat.id, name: goat.name, hatColor: goat.hatColor, bagColor: goat.bagColor }
        : null,
    };
  }

  /** 관리자가 정한 주제: 그 지역 주제 → 레벨 전체('*') 주제 */
  private async topicFor(p: PaperRow): Promise<string | null> {
    const rows = await this.db.rollingTopic.findMany({
      where: { level: p.level, periodStart: p.periodStart, scopeCode: { in: [p.scopeCode, '*'] } },
    });
    return (
      (rows.find((r) => r.scopeCode === p.scopeCode) ?? rows.find((r) => r.scopeCode === '*'))
        ?.topic ?? null
    );
  }

  /** 한마디 남기기. 사진 없음, 장당 1인 1회, 해당 레벨 염소가 내 시에 있을 때만 */
  async join(userId: string, paperId: string, input: { body: string; stickers: PlacedSticker[] }) {
    const paper = await this.db.rollingPaper.findUnique({ where: { id: paperId } });
    if (!paper) throw new AppError(404, 'PAPER_NOT_FOUND', '두루마리를 찾을 수 없어요.');
    const user = await this.db.user.findUniqueOrThrow({ where: { id: userId } });
    const now = this.now();
    if (!user.nickname || !user.birthDate || !user.termsAgreedAt) {
      throw new AppError(403, 'ONBOARDING_REQUIRED', '가입을 마친 뒤에 참여할 수 있어요.');
    }
    if (user.status === 'SUSPENDED' && user.suspendedUntil && user.suspendedUntil > now) {
      throw new AppError(403, 'SUSPENDED', '이용이 잠시 정지된 계정이에요.');
    }
    const entries = await this.db.rollingEntry.findMany({
      where: { paperId },
      include: entryInclude,
    });
    const { block } = await this.joinStatus(userId, paper, entries);
    if (block) throw new AppError(409, block, joinBlockMessage(block, paper.level));
    try {
      const e = await this.db.rollingEntry.create({
        data: {
          paperId,
          authorId: userId,
          body: input.body,
          stickers: input.stickers as unknown as Prisma.InputJsonValue,
        },
        include: entryInclude,
      });
      await this.achievements?.evaluateSafe(userId, METRICS.rolling);
      return entryDto(e, userId);
    } catch (err) {
      // 동시에 두 번 눌렀을 때
      if ((err as { code?: string }).code === 'P2002') {
        throw new AppError(409, 'ALREADY_JOINED', joinBlockMessage('ALREADY_JOINED', paper.level));
      }
      throw err;
    }
  }

  /** 앨범: 내가 참여한 마감된 장(영구 보관, SPEC 6) */
  async album(userId: string) {
    const papers = await this.db.rollingPaper.findMany({
      where: { periodEnd: { lte: this.now() }, entries: { some: { authorId: userId } } },
      include: { _count: { select: { entries: true } } },
      orderBy: { periodEnd: 'desc' },
      take: 200,
    });
    return {
      papers: await Promise.all(
        papers.map(async (p) => ({ ...(await this.paperDto(p)), entryCount: p._count.entries })),
      ),
    };
  }
}

function entryDto(e: EntryRow, viewerId: string) {
  const eaten = e.status === 'EATEN';
  return {
    id: e.id,
    author: {
      id: e.author.id,
      nickname: e.author.nickname ?? DELETED_NAME,
      title: e.author.titleAchievement?.titleText ?? null,
    },
    body: eaten ? null : e.body,
    stickers: eaten ? [] : (e.stickers as unknown as PlacedSticker[]),
    status: e.status,
    mine: e.authorId === viewerId,
    createdAt: e.createdAt.toISOString(),
  };
}

export function joinBlockMessage(block: JoinBlock, level: RollingLevel): string {
  const goat =
    level === 'NATION'
      ? '전국 두루마리 염소'
      : level === 'PROVINCE'
        ? '도 두루마리 염소'
        : '두루마리 염소';
  return {
    ALREADY_JOINED: '이 두루마리에는 이미 한마디를 남겼어요.',
    REGION_UNKNOWN: '지금 있는 시를 확인한 뒤에 참여할 수 있어요.',
    NOT_IN_SCOPE: '이 두루마리는 그 지역에 있을 때만 참여할 수 있어요.',
    NO_GOAT_HERE: `${goat}가 우리 동네에 오면 참여할 수 있어요.`,
    CLOSED: '마감된 두루마리예요.',
  }[block];
}
