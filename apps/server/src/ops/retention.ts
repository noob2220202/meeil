// 백업 보관 규칙(docs/OPERATIONS.md): 최근 N일은 매일 것, 그 이전은 달마다 첫 백업만 M개월.

export interface RetentionPolicy {
  /** 매일 백업을 남기는 기간(일) */
  dailyDays: number;
  /** 달마다 첫 백업을 남기는 기간(개월) */
  monthlyMonths: number;
}

export const DEFAULT_RETENTION: RetentionPolicy = { dailyDays: 30, monthlyMonths: 12 };

const KEY_RE = /^db\/meeil-(\d{4})(\d{2})(\d{2})T(\d{2})(\d{2})Z\.dump(\.enc)?$/;

/** 백업 키 이름: db/meeil-20261004T0300Z.dump.enc */
export function backupKey(at: Date, encrypted = true): string {
  const iso = at.toISOString(); // 2026-10-04T03:00:00.000Z
  const stamp = `${iso.slice(0, 4)}${iso.slice(5, 7)}${iso.slice(8, 10)}T${iso.slice(11, 13)}${iso.slice(14, 16)}Z`;
  return `db/meeil-${stamp}.dump${encrypted ? '.enc' : ''}`;
}

export function parseBackupKey(key: string): Date | null {
  const m = KEY_RE.exec(key);
  if (!m) return null;
  const [, y, mo, d, h, mi] = m;
  return new Date(Date.UTC(+y!, +mo! - 1, +d!, +h!, +mi!));
}

/**
 * 지워도 되는 백업 키. 이름 규칙에 안 맞는 키는 건드리지 않는다.
 * 가장 최근 백업은 정책과 상관없이 늘 남긴다.
 */
export function expiredBackups(
  keys: string[],
  now: Date,
  policy: RetentionPolicy = DEFAULT_RETENTION,
): string[] {
  const dated = keys
    .map((key) => ({ key, at: parseBackupKey(key) }))
    .filter((x): x is { key: string; at: Date } => x.at !== null)
    .sort((a, b) => a.at.getTime() - b.at.getTime());
  if (dated.length === 0) return [];
  const newest = dated[dated.length - 1]!.key;
  const dailyCutoff = now.getTime() - policy.dailyDays * 86_400_000;
  const monthlyCutoff = Date.UTC(now.getUTCFullYear(), now.getUTCMonth() - policy.monthlyMonths, 1);
  const firstOfMonth = new Set<string>();
  const seenMonth = new Set<string>();
  for (const { key, at } of dated) {
    const month = `${at.getUTCFullYear()}-${at.getUTCMonth()}`;
    if (!seenMonth.has(month)) {
      seenMonth.add(month);
      firstOfMonth.add(key);
    }
  }
  return dated
    .filter(({ key, at }) => {
      if (key === newest) return false;
      if (at.getTime() >= dailyCutoff) return false;
      if (firstOfMonth.has(key) && at.getTime() >= monthlyCutoff) return false;
      return true;
    })
    .map((x) => x.key);
}
