import { describe, expect, it } from 'vitest';
import { SOUNDS } from './sounds.js';
import { RATE, wav } from './synth.js';

describe('효과음 합성', () => {
  it.each(Object.keys(SOUNDS))('%s: 짧고, 클리핑 없고, 무음이 아니며, 매번 같다', (name) => {
    const a = SOUNDS[name]!();
    const b = SOUNDS[name]!();
    expect(a).toEqual(b);
    expect(a.length / RATE).toBeGreaterThan(0.2);
    expect(a.length / RATE).toBeLessThan(1.2);
    let peak = 0;
    let energy = 0;
    for (const v of a) {
      peak = Math.max(peak, Math.abs(v));
      energy += v * v;
    }
    expect(peak).toBeLessThanOrEqual(0.9);
    expect(Math.sqrt(energy / a.length)).toBeGreaterThan(0.03);
    // 앞뒤가 0에서 시작·끝(틱 소리 없음)
    expect(Math.abs(a[0]!)).toBeLessThan(0.01);
    expect(Math.abs(a[a.length - 1]!)).toBeLessThan(0.01);
  });

  it('WAV 헤더: 16비트 모노 22050Hz', () => {
    const w = wav(new Float32Array(100));
    expect(w.toString('ascii', 0, 4)).toBe('RIFF');
    expect(w.readUInt16LE(22)).toBe(1);
    expect(w.readUInt32LE(24)).toBe(22050);
    expect(w.readUInt16LE(34)).toBe(16);
    expect(w.length).toBe(44 + 200);
  });
});
