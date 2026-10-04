import { describe, expect, it } from 'vitest';
import { TtlCache } from './ttl-cache.js';

describe('TtlCache', () => {
  it('TTL 동안은 한 번만 불러오고, 지나면 다시 부른다', async () => {
    let t = 0;
    let calls = 0;
    const c = new TtlCache<number>(1000, () => t);
    const load = async () => ++calls;
    const [a, b] = await Promise.all([c.get('k', load), c.get('k', load)]);
    expect([a, b, calls]).toEqual([1, 1, 1]);
    t = 999;
    expect(await c.get('k', load)).toBe(1);
    t = 1000;
    expect(await c.get('k', load)).toBe(2);
  });

  it('실패는 캐시하지 않는다', async () => {
    const c = new TtlCache<number>(1000, () => 0);
    await expect(c.get('k', () => Promise.reject(new Error('x')))).rejects.toThrow('x');
    await Promise.resolve();
    expect(await c.get('k', async () => 7)).toBe(7);
  });
});
