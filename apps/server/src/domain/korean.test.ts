import { describe, expect, it } from 'vitest';
import { iGa } from './korean.js';

describe('iGa', () => {
  it('받침에 따라 이/가', () => {
    expect(iGa('찰떡')).toBe('찰떡이');
    expect(iGa('메롱이')).toBe('메롱이가');
    expect(iGa('구름')).toBe('구름이');
    expect(iGa('우유')).toBe('우유가');
  });
});
