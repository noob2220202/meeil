import { describe, expect, it } from 'vitest';
import { ageOn, isValidBirthDate, kstToday } from './age.js';

describe('kstToday', () => {
  it('UTC 15시 이후는 KST 다음 날', () => {
    expect(kstToday(new Date('2026-10-02T14:59:59Z'))).toEqual([2026, 10, 2]);
    expect(kstToday(new Date('2026-10-02T15:00:00Z'))).toEqual([2026, 10, 3]);
  });
});

describe('ageOn (만 나이, KST)', () => {
  const now = new Date('2026-10-02T15:30:00Z'); // KST 2026-10-03
  it('생일 당일부터 한 살 더한다', () => {
    expect(ageOn('2012-10-03', now)).toBe(14);
    expect(ageOn('2012-10-04', now)).toBe(13);
    expect(ageOn('2012-09-30', now)).toBe(14);
  });
  it('UTC 날짜가 아니라 KST 날짜 기준', () => {
    // UTC로는 아직 10-02지만 KST로는 10-03이므로 14세
    expect(ageOn('2012-10-03', new Date('2026-10-02T15:00:00Z'))).toBe(14);
    expect(ageOn('2012-10-03', new Date('2026-10-02T14:59:00Z'))).toBe(13);
  });
});

describe('isValidBirthDate', () => {
  const now = new Date('2026-10-03T00:00:00Z');
  it('없는 날짜·미래·너무 오래된 날짜는 거부', () => {
    expect(isValidBirthDate('2010-02-30', now)).toBe(false);
    expect(isValidBirthDate('2030-01-01', now)).toBe(false);
    expect(isValidBirthDate('1800-01-01', now)).toBe(false);
    expect(isValidBirthDate('2010-2-3', now)).toBe(false);
    expect(isValidBirthDate('2000-02-29', now)).toBe(true);
  });
});
