import { describe, expect, it } from 'vitest';
import { backupKey, expiredBackups, parseBackupKey } from './retention.js';

const day = (iso: string) => backupKey(new Date(`${iso}T18:00:00Z`)); // 매일 03:00 KST

describe('백업 키', () => {
  it('이름 ↔ 시각', () => {
    const at = new Date('2026-10-04T18:05:00Z');
    expect(backupKey(at)).toBe('db/meeil-20261004T1805Z.dump.enc');
    expect(backupKey(at, false)).toBe('db/meeil-20261004T1805Z.dump');
    expect(parseBackupKey(backupKey(at))?.toISOString()).toBe(at.toISOString());
    expect(parseBackupKey('db/other.txt')).toBeNull();
  });
});

describe('보관 규칙(30일 매일 + 12개월 월초)', () => {
  // 2025-09-01부터 2026-10-04까지 매일 백업
  const keys: string[] = [];
  for (let t = Date.UTC(2025, 8, 1); t <= Date.UTC(2026, 9, 4); t += 86_400_000) {
    keys.push(day(new Date(t).toISOString().slice(0, 10)));
  }
  const now = new Date('2026-10-04T19:00:00Z');
  const expired = new Set(expiredBackups([...keys, 'db/README.txt'], now));
  const kept = keys.filter((k) => !expired.has(k));

  it('최근 30일은 전부 남긴다', () => {
    for (let i = 0; i < 30; i++) {
      const d = new Date(now.getTime() - i * 86_400_000).toISOString().slice(0, 10);
      expect(kept).toContain(day(d));
    }
  });

  it('그 이전은 달마다 첫 백업만, 12개월까지', () => {
    expect(kept).toContain(day('2026-08-01'));
    expect(kept).toContain(day('2025-10-01'));
    expect(kept).not.toContain(day('2026-08-02'));
    expect(kept).not.toContain(day('2025-09-01')); // 13개월 전
    expect(kept.length).toBe(30 + 1 /* 9/4 이전 9월 1일 */ + 11);
  });

  it('이름 규칙 밖의 키와 가장 최근 백업은 지우지 않는다', () => {
    expect(expired.has('db/README.txt')).toBe(false);
    const old = [day('2020-01-05')];
    expect(expiredBackups(old, now)).toEqual([]);
    expect(expiredBackups([], now)).toEqual([]);
  });
});
