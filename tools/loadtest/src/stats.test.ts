import { describe, expect, it } from 'vitest';
import { Histogram, judge } from './stats.js';

describe('Histogram', () => {
  it('백분위는 최근접 순위 방식', () => {
    const h = new Histogram();
    for (let i = 1; i <= 100; i++) h.record(i, 200);
    expect(h.percentile(50)).toBe(50);
    expect(h.percentile(95)).toBe(95);
    expect(h.percentile(99)).toBe(99);
    expect(h.percentile(100)).toBe(100);
  });

  it('업무상 4xx는 오류로 세지 않는다', () => {
    const h = new Histogram();
    h.record(5, 201);
    h.record(5, 409, [409]);
    h.record(5, 500);
    h.record(5, 404);
    expect([h.ok, h.expected, h.errors]).toEqual([1, 1, 2]);
  });

  it('기준 판정', () => {
    const fast = new Histogram();
    for (let i = 0; i < 1000; i++) fast.record(20, 200);
    expect(judge(fast)).toEqual([]);
    const slow = new Histogram();
    for (let i = 0; i < 1000; i++) slow.record(i < 900 ? 20 : 900, i < 995 ? 200 : 503);
    const fails = judge(slow);
    expect(fails.some((f) => f.startsWith('p95'))).toBe(true);
    expect(fails.some((f) => f.startsWith('p99'))).toBe(true);
    expect(fails.some((f) => f.startsWith('오류율'))).toBe(true);
    expect(judge(new Histogram())).toHaveLength(1);
  });

  it('merge', () => {
    const a = new Histogram();
    const b = new Histogram();
    a.record(1, 200);
    b.record(3, 500);
    a.merge(b);
    expect(a.count).toBe(2);
    expect(a.errors).toBe(1);
    expect(a.codes.get(500)).toBe(1);
  });
});
