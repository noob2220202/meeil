// 아주 작은 합성기: 오실레이터, 잡음, 바이쿼드 필터, 엔벨로프, WAV 쓰기.
// 모든 효과음은 이 코드로 만든다(외부 녹음·샘플 없음).

export const RATE = 22050;

export type Buf = Float32Array;

export const seconds = (s: number) => Math.round(s * RATE);

/** 결정적 난수(같은 입력이면 같은 소리) */
export function rng(seed: number) {
  let s = seed >>> 0 || 1;
  return () => {
    s ^= s << 13;
    s ^= s >>> 17;
    s ^= s << 5;
    return ((s >>> 0) / 0xffffffff) * 2 - 1;
  };
}

export function noise(len: number, seed = 1): Buf {
  const r = rng(seed);
  const out = new Float32Array(len);
  for (let i = 0; i < len; i++) out[i] = r();
  return out;
}

/** 주파수 함수 f(t)를 따라가는 오실레이터. shape: 0=사인, 1=톱니(대역 제한 근사) */
export function osc(len: number, freq: (t: number) => number, harmonics = 1): Buf {
  const out = new Float32Array(len);
  let phase = 0;
  for (let i = 0; i < len; i++) {
    const t = i / RATE;
    const f = freq(t);
    phase += (2 * Math.PI * f) / RATE;
    let v = 0;
    // 나이퀴스트를 넘지 않는 배음만 더한 톱니
    for (let h = 1; h <= harmonics && h * f < RATE / 2; h++) v += Math.sin(phase * h) / h;
    out[i] = v;
  }
  return out;
}

/** RBJ 바이쿼드 */
export function biquad(
  input: Buf,
  type: 'lowpass' | 'highpass' | 'bandpass',
  freq: number,
  q = 0.707,
): Buf {
  const w = (2 * Math.PI * freq) / RATE;
  const alpha = Math.sin(w) / (2 * q);
  const cos = Math.cos(w);
  let b0: number, b1: number, b2: number;
  if (type === 'lowpass') {
    b0 = (1 - cos) / 2;
    b1 = 1 - cos;
    b2 = (1 - cos) / 2;
  } else if (type === 'highpass') {
    b0 = (1 + cos) / 2;
    b1 = -(1 + cos);
    b2 = (1 + cos) / 2;
  } else {
    b0 = alpha;
    b1 = 0;
    b2 = -alpha;
  }
  const a0 = 1 + alpha;
  const a1 = -2 * cos;
  const a2 = 1 - alpha;
  const out = new Float32Array(input.length);
  let x1 = 0,
    x2 = 0,
    y1 = 0,
    y2 = 0;
  for (let i = 0; i < input.length; i++) {
    const x = input[i]!;
    const y = (b0 * x + b1 * x1 + b2 * x2 - a1 * y1 - a2 * y2) / a0;
    out[i] = y;
    x2 = x1;
    x1 = x;
    y2 = y1;
    y1 = y;
  }
  return out;
}

/** 시간 함수 g(t)를 곱한다 */
export function shape(input: Buf, g: (t: number) => number): Buf {
  const out = new Float32Array(input.length);
  for (let i = 0; i < input.length; i++) out[i] = input[i]! * g(i / RATE);
  return out;
}

/** attack·decay 엔벨로프(초) */
export const adsr =
  (attack: number, hold: number, release: number) =>
  (t: number): number => {
    if (t < attack) return t / attack;
    if (t < attack + hold) return 1;
    const r = (t - attack - hold) / release;
    return r >= 1 ? 0 : (1 - r) ** 2;
  };

export const expDecay = (tau: number) => (t: number) => Math.exp(-t / tau);

export function mix(len: number, ...parts: [Buf, number, number?][]): Buf {
  const out = new Float32Array(len);
  for (const [b, gain, offset = 0] of parts) {
    const o = seconds(offset);
    for (let i = 0; i < b.length && i + o < len; i++) out[i + o]! += b[i]! * gain;
  }
  return out;
}

export function add(a: Buf, b: Buf, gain = 1): Buf {
  const out = new Float32Array(Math.max(a.length, b.length));
  for (let i = 0; i < out.length; i++) out[i] = (a[i] ?? 0) + (b[i] ?? 0) * gain;
  return out;
}

/** 최대 진폭을 [peak]로 맞추고 앞뒤 5ms 페이드(틱 소리 방지) */
export function normalize(input: Buf, peak = 0.85): Buf {
  let max = 0;
  for (const v of input) max = Math.max(max, Math.abs(v));
  const k = max > 0 ? peak / max : 0;
  const fade = seconds(0.005);
  const out = new Float32Array(input.length);
  for (let i = 0; i < input.length; i++) {
    const edge = Math.min(1, i / fade, (input.length - 1 - i) / fade);
    out[i] = input[i]! * k * edge;
  }
  return out;
}

/** 16비트 PCM 모노 WAV */
export function wav(samples: Buf): Buffer {
  const data = Buffer.alloc(samples.length * 2);
  for (let i = 0; i < samples.length; i++) {
    const v = Math.max(-1, Math.min(1, samples[i]!));
    data.writeInt16LE(Math.round(v * 32767), i * 2);
  }
  const h = Buffer.alloc(44);
  h.write('RIFF', 0);
  h.writeUInt32LE(36 + data.length, 4);
  h.write('WAVE', 8);
  h.write('fmt ', 12);
  h.writeUInt32LE(16, 16);
  h.writeUInt16LE(1, 20); // PCM
  h.writeUInt16LE(1, 22); // 모노
  h.writeUInt32LE(RATE, 24);
  h.writeUInt32LE(RATE * 2, 28);
  h.writeUInt16LE(2, 32);
  h.writeUInt16LE(16, 34);
  h.write('data', 36);
  h.writeUInt32LE(data.length, 40);
  return Buffer.concat([h, data]);
}
