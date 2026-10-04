// 출석 체크 (SPEC 7.1): 하루 +3P, 7일 연속마다 +5P 추가. 날짜는 KST.
import type { Db } from '../db.js';
import { kstToday } from '../domain/age.js';
import { POINTS, applyLedger, lockUser } from '../domain/points.js';

const DAY = 24 * 60 * 60 * 1000;

/** KST 날짜 → DB의 date 값(UTC 자정) */
function kstDate(now: Date): Date {
  const [y, m, d] = kstToday(now);
  return new Date(Date.UTC(y, m - 1, d));
}

const ymd = (d: Date) => d.toISOString().slice(0, 10);

export class AttendanceService {
  constructor(
    private readonly db: Db,
    private readonly now: () => Date,
  ) {}

  /** 오늘 출석. 이미 했으면 그대로 돌려준다(포인트 중복 없음). */
  async check(userId: string) {
    const today = kstDate(this.now());
    const result = await this.db.$transaction(async (tx) => {
      await lockUser(tx, userId);
      const existing = await tx.attendance.findUnique({
        where: { userId_date: { userId, date: today } },
      });
      if (existing) return { checkedIn: false, streak: existing.streak, rewards: [] as Reward[] };
      const yesterday = await tx.attendance.findUnique({
        where: { userId_date: { userId, date: new Date(today.getTime() - DAY) } },
      });
      const streak = (yesterday?.streak ?? 0) + 1;
      await tx.attendance.create({ data: { userId, date: today, streak } });
      const rewards: Reward[] = [{ reason: 'ATTENDANCE', points: POINTS.ATTENDANCE }];
      await applyLedger(tx, {
        userId,
        delta: POINTS.ATTENDANCE,
        reason: 'ATTENDANCE',
        idempotencyKey: `attend:${userId}:${ymd(today)}`,
        at: this.now(),
      });
      if (streak % POINTS.STREAK_DAYS === 0) {
        rewards.push({ reason: 'ATTENDANCE_STREAK', points: POINTS.ATTENDANCE_STREAK_BONUS });
        await applyLedger(tx, {
          userId,
          delta: POINTS.ATTENDANCE_STREAK_BONUS,
          reason: 'ATTENDANCE_STREAK',
          idempotencyKey: `streak:${userId}:${ymd(today)}`,
          at: this.now(),
        });
      }
      return { checkedIn: true, streak, rewards };
    });
    return { ...result, ...(await this.status(userId)) };
  }

  /** 달력: 이번 달(또는 [month] 'YYYY-MM') 출석한 날, 연속 일수, 총 일수 */
  async status(userId: string, month?: string) {
    const today = kstDate(this.now());
    const [y, m] = month
      ? month.split('-').map(Number)
      : [today.getUTCFullYear(), today.getUTCMonth() + 1];
    const from = new Date(Date.UTC(y!, m! - 1, 1));
    const to = new Date(Date.UTC(y!, m!, 1));
    const [days, total, latest] = await Promise.all([
      this.db.attendance.findMany({
        where: { userId, date: { gte: from, lt: to } },
        orderBy: { date: 'asc' },
      }),
      this.db.attendance.count({ where: { userId } }),
      this.db.attendance.findFirst({ where: { userId }, orderBy: { date: 'desc' } }),
    ]);
    // 어제나 오늘 출석했으면 연속이 이어지는 중
    const alive = latest && today.getTime() - latest.date.getTime() <= DAY;
    const streak = alive ? latest.streak : 0;
    return {
      today: ymd(today),
      month: `${y}-${String(m).padStart(2, '0')}`,
      checkedToday: latest ? ymd(latest.date) === ymd(today) : false,
      streak,
      /** 다음 연속 보너스까지 남은 날(오늘 출석 전이면 오늘 포함) */
      daysToStreakBonus: POINTS.STREAK_DAYS - (streak % POINTS.STREAK_DAYS),
      totalDays: total,
      days: days.map((d) => ymd(d.date)),
      points: {
        daily: POINTS.ATTENDANCE,
        streakBonus: POINTS.ATTENDANCE_STREAK_BONUS,
        streakDays: POINTS.STREAK_DAYS,
      },
    };
  }
}

interface Reward {
  reason: 'ATTENDANCE' | 'ATTENDANCE_STREAK';
  points: number;
}
