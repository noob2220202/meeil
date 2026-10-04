// 업적 판정·지급 (SPEC 7.3): 포인트 + 칭호 + 편지지 해금
import { ACHIEVEMENTS, type AchievementDef, type Metric } from '../catalog/achievements.js';
import type { Db } from '../db.js';
import { applyLedger } from '../domain/points.js';
import { Prisma } from '../generated/prisma/client.js';

const JEJU_PROVINCE = '50';
const ULLEUNG_REGION = '47940';

export type Stats = Partial<Record<Metric, number>>;

/** 업적 묶음별로 다시 셀 지표. 이벤트가 생길 때 해당 묶음만 판정한다. */
export const METRICS = {
  letterSent: [
    'lettersSent',
    'repliesSent',
    'midnightLetters',
    'photoLetters',
    'penPalMax',
    'goatsMet',
  ],
  letterReceived: ['lettersReceived', 'goatsMet', 'penPalMax'],
  rolling: ['rollingEntries'],
  visit: ['provincesVisited', 'citiesVisited', 'jejuVisited', 'ulleungVisited'],
  attendance: ['attendanceDays'],
} satisfies Record<string, Metric[]>;

export interface UnlockedDto {
  id: string;
  name: string;
  description: string;
  rewardPoints: number;
  titleText: string | null;
  stationeryId: string | null;
  stationeryName: string | null;
}

export class AchievementService {
  constructor(
    private readonly db: Db,
    private readonly now: () => Date,
  ) {}

  /** 'ALL' 목표의 실제 값 */
  private async allTargets() {
    const [provinces, goats] = await Promise.all([
      this.db.province.count(),
      this.db.goat.count({ where: { kind: 'DELIVERY', active: true } }),
    ]);
    return { provincesVisited: provinces, goatsMet: goats } as Partial<Record<Metric, number>>;
  }

  async targetOf(def: AchievementDef, all?: Partial<Record<Metric, number>>): Promise<number> {
    if (def.target !== 'ALL') return def.target;
    return (all ?? (await this.allTargets()))[def.metric] ?? Number.MAX_SAFE_INTEGER;
  }

  /** 지표 값 세기(요청한 것만) */
  async stats(userId: string, metrics: readonly Metric[]): Promise<Stats> {
    const want = new Set(metrics);
    const out: Stats = {};
    const db = this.db;
    const tasks: Promise<void>[] = [];
    const add = (m: Metric, f: () => Promise<number>) => {
      if (want.has(m)) tasks.push(f().then((v) => void (out[m] = v)));
    };
    add('lettersSent', () => db.letter.count({ where: { senderId: userId } }));
    add('repliesSent', () => db.letter.count({ where: { senderId: userId, mode: 'REPLY' } }));
    add('photoLetters', () =>
      db.letter.count({ where: { senderId: userId, photo: { isNot: null } } }),
    );
    add('lettersReceived', () =>
      db.letter.count({
        where: { recipientId: userId, deliveredAt: { not: null }, hiddenForRecipient: false },
      }),
    );
    add('rollingEntries', () => db.rollingEntry.count({ where: { authorId: userId } }));
    add('attendanceDays', () => db.attendance.count({ where: { userId } }));
    add('citiesVisited', () => db.regionVisit.count({ where: { userId } }));
    add('provincesVisited', async () => {
      const rows = await db.region.findMany({
        where: { visits: { some: { userId } } },
        select: { provinceCode: true },
        distinct: ['provinceCode'],
      });
      return rows.length;
    });
    add('jejuVisited', () =>
      db.regionVisit.count({ where: { userId, region: { provinceCode: JEJU_PROVINCE } } }),
    );
    add('ulleungVisited', () =>
      db.regionVisit.count({ where: { userId, regionCode: ULLEUNG_REGION } }),
    );
    add('midnightLetters', async () => {
      // 한국 시각 0~4시(0:00~3:59)에 맡긴 편지
      const [r] = await db.$queryRaw<{ n: bigint }[]>(Prisma.sql`
        SELECT count(*) AS n FROM letters
        WHERE "senderId" = ${userId}::uuid
          AND extract(hour FROM ("handedAt" AT TIME ZONE 'UTC') AT TIME ZONE 'Asia/Seoul') < 4`);
      return Number(r?.n ?? 0);
    });
    add('penPalMax', async () => {
      // 같은 사람과 주고받은 횟수 = min(보낸 수, 받은 수)의 최댓값
      const [r] = await db.$queryRaw<{ n: bigint | null }[]>(Prisma.sql`
        WITH sent AS (
          SELECT "recipientId" AS other, count(*) AS c FROM letters
          WHERE "senderId" = ${userId}::uuid GROUP BY 1
        ), got AS (
          SELECT "senderId" AS other, count(*) AS c FROM letters
          WHERE "recipientId" = ${userId}::uuid AND "deliveredAt" IS NOT NULL
            AND "hiddenForRecipient" = false GROUP BY 1
        )
        SELECT max(least(sent.c, got.c)) AS n FROM sent JOIN got USING (other)`);
      return Number(r?.n ?? 0);
    });
    add('goatsMet', async () => {
      // 편지를 맡긴 염소 + 편지를 가져다준 염소(배달 염소만)
      const [r] = await db.$queryRaw<{ n: bigint }[]>(Prisma.sql`
        SELECT count(DISTINCT g.id) AS n FROM goats g
        WHERE g.kind = 'DELIVERY' AND g.id IN (
          SELECT "pickupGoatId" FROM letters WHERE "senderId" = ${userId}::uuid AND "pickupGoatId" IS NOT NULL
          UNION
          SELECT "goatId" FROM letters WHERE "recipientId" = ${userId}::uuid
            AND "deliveredAt" IS NOT NULL AND "goatId" IS NOT NULL
        )`);
      return Number(r?.n ?? 0);
    });
    await Promise.all(tasks);
    return out;
  }

  /**
   * [metrics]로 판정되는 업적 중 새로 달성한 것을 지급한다. 여러 번 불러도 한 번만 지급.
   * 실패해도 본 동작(편지 맡기기 등)을 막지 않도록 호출하는 쪽은 [evaluateSafe]를 쓴다.
   */
  async evaluate(userId: string, metrics: readonly Metric[]): Promise<string[]> {
    const candidates = ACHIEVEMENTS.filter((a) => metrics.includes(a.metric));
    if (candidates.length === 0) return [];
    const have = new Set(
      (
        await this.db.userAchievement.findMany({
          where: { userId, achievementId: { in: candidates.map((a) => a.id) } },
          select: { achievementId: true },
        })
      ).map((r) => r.achievementId),
    );
    const open = candidates.filter((a) => !have.has(a.id));
    if (open.length === 0) return [];
    const stats = await this.stats(userId, [...new Set(open.map((a) => a.metric))]);
    const all = open.some((a) => a.target === 'ALL') ? await this.allTargets() : undefined;
    const won: string[] = [];
    for (const a of open) {
      if ((stats[a.metric] ?? 0) < (await this.targetOf(a, all))) continue;
      if (await this.grant(userId, a.id)) won.push(a.id);
    }
    return won;
  }

  async evaluateSafe(
    userId: string,
    metrics: readonly Metric[],
    log?: { warn: (o: object, m: string) => void },
  ): Promise<string[]> {
    try {
      return await this.evaluate(userId, metrics);
    } catch (err) {
      log?.warn({ err, userId }, 'achievement evaluate failed');
      return [];
    }
  }

  /** 업적 하나 지급: 기록 + 포인트 + 편지지. 이미 있으면 false */
  async grant(userId: string, achievementId: string): Promise<boolean> {
    try {
      return await this.db.$transaction(async (tx) => {
        const a = await tx.achievement.findUniqueOrThrow({ where: { id: achievementId } });
        await tx.userAchievement.create({
          data: { userId, achievementId, achievedAt: this.now() },
        });
        if (a.rewardPoints > 0) {
          await applyLedger(tx, {
            userId,
            delta: a.rewardPoints,
            reason: 'ACHIEVEMENT',
            idempotencyKey: `ach:${userId}:${a.id}`,
            refId: a.id,
            at: this.now(),
          });
        }
        if (a.unlocksStationeryId) {
          await tx.userStationery.createMany({
            data: [{ userId, stationeryId: a.unlocksStationeryId, unlockedAt: this.now() }],
            skipDuplicates: true,
          });
        }
        return true;
      });
    } catch (err) {
      if (err instanceof Prisma.PrismaClientKnownRequestError && err.code === 'P2002') return false;
      throw err;
    }
  }

  /** 업적 목록 + 진행도 */
  async list(userId: string) {
    const [rows, mine, user, stats, all] = await Promise.all([
      this.db.achievement.findMany({
        orderBy: { sortOrder: 'asc' },
        include: { unlocksStationery: { select: { name: true } } },
      }),
      this.db.userAchievement.findMany({ where: { userId } }),
      this.db.user.findUniqueOrThrow({
        where: { id: userId },
        select: { titleAchievementId: true },
      }),
      this.stats(
        userId,
        ACHIEVEMENTS.map((a) => a.metric),
      ),
      this.allTargets(),
    ]);
    const got = new Map(mine.map((m) => [m.achievementId, m.achievedAt]));
    const defs = new Map(ACHIEVEMENTS.map((a) => [a.id, a]));
    return {
      titleAchievementId: user.titleAchievementId,
      achievements: await Promise.all(
        rows.map(async (a) => {
          const def = defs.get(a.id);
          const target = def ? await this.targetOf(def, all) : 1;
          const current = def ? Math.min(stats[def.metric] ?? 0, target) : 0;
          const at = got.get(a.id);
          return {
            id: a.id,
            name: a.name,
            description: a.description,
            rewardPoints: a.rewardPoints,
            titleText: a.titleText,
            stationeryId: a.unlocksStationeryId,
            stationeryName: a.unlocksStationery?.name ?? null,
            achieved: Boolean(at),
            achievedAt: at?.toISOString() ?? null,
            progress: { current: at ? target : current, target },
          };
        }),
      ),
    };
  }

  /** 아직 축하를 못 본 업적(앱이 띄우고 seen 처리) */
  async unseen(userId: string): Promise<UnlockedDto[]> {
    const rows = await this.db.userAchievement.findMany({
      where: { userId, seenAt: null },
      include: { achievement: { include: { unlocksStationery: { select: { name: true } } } } },
      orderBy: { achievedAt: 'asc' },
    });
    return rows.map(({ achievement: a }) => ({
      id: a.id,
      name: a.name,
      description: a.description,
      rewardPoints: a.rewardPoints,
      titleText: a.titleText,
      stationeryId: a.unlocksStationeryId,
      stationeryName: a.unlocksStationery?.name ?? null,
    }));
  }

  async markSeen(userId: string, ids: string[]): Promise<void> {
    await this.db.userAchievement.updateMany({
      where: { userId, achievementId: { in: ids }, seenAt: null },
      data: { seenAt: this.now() },
    });
  }
}
