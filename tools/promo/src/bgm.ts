// 홍보 영상 배경음악(약 11초, 120BPM, C-G-Am-F-C). 녹음·샘플 없이 합성한다.
//   pnpm --filter @meeil/tools-promo bgm  → build/promo/bgm.wav
import { mkdirSync, writeFileSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';

const RATE = 44100;
const BPM = 120;
const BEAT = 60 / BPM;
const LEN = 11.0;
const out = new Float32Array(Math.round(LEN * RATE));

const midi = (n: number) => 440 * 2 ** ((n - 69) / 12);

/** 결정적 난수 */
let seed = 7;
const rnd = () => {
  seed ^= seed << 13;
  seed ^= seed >>> 17;
  seed ^= seed << 5;
  return ((seed >>> 0) / 0xffffffff) * 2 - 1;
};

function addAt(t: number, buf: Float32Array, gain: number) {
  const o = Math.round(t * RATE);
  for (let i = 0; i < buf.length && o + i < out.length; i++) out[o + i]! += buf[i]! * gain;
}

/** 카플러스-스트롱 뜯는 줄(우쿨렐레 느낌) */
function pluck(freq: number, dur: number, bright = 0.5): Float32Array {
  const n = Math.round(dur * RATE);
  const period = Math.max(2, Math.round(RATE / freq));
  const line = new Float32Array(period);
  for (let i = 0; i < period; i++) line[i] = rnd() * (0.5 + bright * 0.5);
  const res = new Float32Array(n);
  let idx = 0;
  for (let i = 0; i < n; i++) {
    const a = line[idx]!;
    const b = line[(idx + 1) % period]!;
    line[idx] = 0.996 * (0.5 * (a + b));
    res[i] = a;
    idx = (idx + 1) % period;
  }
  return res;
}

/** 글로켄슈필: 맑은 배음 + 빠른 감쇠 */
function glock(freq: number, dur: number): Float32Array {
  const n = Math.round(dur * RATE);
  const res = new Float32Array(n);
  for (let i = 0; i < n; i++) {
    const t = i / RATE;
    const env = Math.min(1, t / 0.003) * Math.exp(-t / 0.35);
    res[i] =
      env *
      (Math.sin(2 * Math.PI * freq * t) +
        0.35 * Math.sin(2 * Math.PI * freq * 2.76 * t) * Math.exp(-t / 0.08) +
        0.15 * Math.sin(2 * Math.PI * freq * 5.4 * t) * Math.exp(-t / 0.04));
  }
  return res;
}

function kick(): Float32Array {
  const n = Math.round(0.25 * RATE);
  const res = new Float32Array(n);
  let ph = 0;
  for (let i = 0; i < n; i++) {
    const t = i / RATE;
    ph += (2 * Math.PI * (55 + 90 * Math.exp(-t * 30))) / RATE;
    res[i] = Math.sin(ph) * Math.exp(-t / 0.09);
  }
  return res;
}

function shaker(): Float32Array {
  const n = Math.round(0.06 * RATE);
  const res = new Float32Array(n);
  let prev = 0;
  for (let i = 0; i < n; i++) {
    const t = i / RATE;
    const w = rnd();
    const hp = w - prev; // 간단한 하이패스
    prev = w;
    res[i] = hp * Math.sin(Math.PI * Math.min(1, t / 0.06)) * 0.5;
  }
  return res;
}

// 코드(루트 MIDI + 구성음): 한 마디 4박
const C = [60, 64, 67, 72];
const G = [55, 59, 62, 67];
const Am = [57, 60, 64, 69];
const F = [53, 57, 60, 65];
const bars = [C, G, Am, F, C];
const bass = [36, 43, 45, 41, 36];

// 멜로디(박 단위 시작, MIDI, 길이)
const melody: [number, number, number][] = [
  [0, 76, 0.5],
  [0.5, 79, 0.5],
  [1, 84, 1],
  [2, 79, 0.5],
  [2.5, 76, 0.5],
  [3, 79, 1],
  [4, 74, 0.5],
  [4.5, 79, 0.5],
  [5, 83, 1],
  [6, 81, 0.5],
  [6.5, 79, 0.5],
  [7, 74, 1],
  [8, 76, 0.5],
  [8.5, 81, 0.5],
  [9, 84, 1],
  [10, 83, 0.5],
  [10.5, 81, 0.5],
  [11, 76, 1],
  [12, 77, 0.5],
  [12.5, 81, 0.5],
  [13, 84, 0.5],
  [13.5, 86, 0.5],
  [14, 84, 1],
  [15, 81, 0.5],
  [15.5, 79, 0.5],
  [16, 84, 0.25],
  [16.25, 88, 0.25],
  [16.5, 91, 2],
];

const start = 0.35; // 영상 첫 장면과 맞춘 여유
bars.forEach((chord, b) => {
  const t0 = start + b * 4 * BEAT;
  const last = b === bars.length - 1;
  // 우쿨렐레 스트럼: 아래-위 8분음표(마지막 마디는 한 번 길게)
  const strums = last ? [0] : [0, 0.5, 1, 1.5, 2, 2.5, 3, 3.5];
  strums.forEach((beat, k) => {
    const up = k % 2 === 1;
    const notes = up ? [...chord].reverse() : chord;
    notes.forEach((n, j) =>
      addAt(
        t0 + beat * BEAT + j * 0.012,
        pluck(midi(n), last ? 2.5 : 0.6, up ? 0.3 : 0.7),
        up ? 0.09 : 0.13,
      ),
    );
  });
  addAt(t0, pluck(midi(bass[b]!), last ? 2.5 : 2 * BEAT, 0.8), 0.28);
  if (!last) {
    addAt(t0, kick(), 0.5);
    addAt(t0 + 2 * BEAT, kick(), 0.45);
    for (let e = 0; e < 8; e++) addAt(t0 + e * 0.5 * BEAT, shaker(), e % 2 ? 0.08 : 0.12);
  }
});
for (const [beat, n, len] of melody)
  addAt(start + beat * BEAT, glock(midi(n), Math.max(0.6, len * BEAT * 1.6)), 0.22);

// 아주 짧은 잔향(피드백 딜레이 두 개)
for (const [d, g] of [
  [0.083, 0.22],
  [0.137, 0.15],
] as const) {
  const k = Math.round(d * RATE);
  for (let i = k; i < out.length; i++) out[i]! += out[i - k]! * g;
}

// 정규화 + 끝 1초 페이드아웃
let peak = 0;
for (const v of out) peak = Math.max(peak, Math.abs(v));
const fadeFrom = out.length - RATE;
for (let i = 0; i < out.length; i++) {
  const fade = i > fadeFrom ? 1 - (i - fadeFrom) / RATE : 1;
  const fadeIn = Math.min(1, i / (0.01 * RATE));
  out[i] = Math.tanh((out[i]! / peak) * 1.1) * 0.8 * fade * fadeIn;
}

const data = Buffer.alloc(out.length * 2);
for (let i = 0; i < out.length; i++) data.writeInt16LE(Math.round(out[i]! * 32767), i * 2);
const h = Buffer.alloc(44);
h.write('RIFF', 0);
h.writeUInt32LE(36 + data.length, 4);
h.write('WAVEfmt ', 8);
h.writeUInt32LE(16, 16);
h.writeUInt16LE(1, 20);
h.writeUInt16LE(1, 22);
h.writeUInt32LE(RATE, 24);
h.writeUInt32LE(RATE * 2, 28);
h.writeUInt16LE(2, 32);
h.writeUInt16LE(16, 34);
h.write('data', 36);
h.writeUInt32LE(data.length, 40);
const root = join(dirname(fileURLToPath(import.meta.url)), '../../..');
const dest = join(root, 'apps/mobile/build/promo/bgm.wav');
mkdirSync(dirname(dest), { recursive: true });
writeFileSync(dest, Buffer.concat([h, data]));
console.log(`bgm.wav ${(out.length / RATE).toFixed(1)}s`);
