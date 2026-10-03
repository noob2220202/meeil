// 메에일 효과음 6종 (SPEC 12.3): 염소 울음 2, 편지 열기, 도장, 포인트, 먹는 소리
import {
  adsr,
  biquad,
  expDecay,
  mix,
  noise,
  normalize,
  osc,
  seconds,
  shape,
  add,
  type Buf,
} from './synth.js';

/**
 * 염소 울음 "메에~": 떨리는 목소리(빠른 비브라토+트레몰로) + "에" 모음 포먼트.
 * [base] 기본 음높이, [pulses] 끊어 우는 횟수.
 */
function bleat(base: number, dur: number, pulses: number, seed: number): Buf {
  const len = seconds(dur);
  // 떨림: 16~20Hz로 음높이와 세기가 함께 흔들리는 게 염소 울음의 특징
  const flutter = (t: number) => Math.sin(2 * Math.PI * (17 + 2 * t) * t);
  const pitch = (t: number) =>
    base * (1 + 0.06 * flutter(t)) * (1 + 0.12 * Math.exp(-t * 6)) * (1 - 0.08 * (t / dur));
  const voice = osc(len, pitch, 24);
  // "에": F1 ~600Hz, F2 ~1900Hz, F3 ~2600Hz
  const f1 = biquad(voice, 'bandpass', 620, 5);
  const f2 = biquad(voice, 'bandpass', 1900, 7);
  const f3 = biquad(voice, 'bandpass', 2700, 9);
  // 고음을 깎아 둥글고 귀엽게
  let v = biquad(add(add(f1, f2, 0.8), f3, 0.35), 'lowpass', 3200, 0.8);
  // 숨소리 조금
  v = add(v, biquad(noise(len, seed), 'bandpass', 2200, 1.2), 0.04);
  const seg = dur / pulses;
  v = shape(v, (t) => {
    const i = Math.min(pulses - 1, Math.floor(t / seg));
    const local = t - i * seg;
    const env = adsr(0.03, seg * 0.45, seg * 0.45)(local);
    return env * (0.75 + 0.25 * Math.sin(2 * Math.PI * 17 * t)) * (i === 0 ? 1 : 0.85);
  });
  return normalize(v, 0.8);
}

/** 봉투를 여는 바스락 + 작은 띵 */
function letterOpen(): Buf {
  const len = seconds(0.55);
  const rustle = shape(biquad(biquad(noise(len, 3), 'highpass', 1800), 'lowpass', 6500), (t) => {
    // 바스락 세 번
    const bursts = [0, 0.09, 0.2].map((s) => (t >= s ? Math.exp(-(t - s) / 0.045) : 0));
    return bursts.reduce((a, b) => a + b, 0) * 0.6;
  });
  const ding = shape(
    osc(len, () => 1568, 3),
    (t) => (t > 0.25 ? Math.exp(-(t - 0.25) / 0.12) : 0),
  );
  return normalize(mix(len, [rustle, 1], [ding, 0.35]), 0.75);
}

/** 도장 쾅: 낮은 쿵 + 종이 탁 */
function stamp(): Buf {
  const len = seconds(0.3);
  const thump = shape(
    osc(len, (t) => 150 * Math.exp(-t * 8) + 70, 2),
    expDecay(0.06),
  );
  const slap = shape(biquad(noise(len, 5), 'bandpass', 1400, 0.8), expDecay(0.018));
  return normalize(mix(len, [thump, 1], [slap, 0.7]), 0.85);
}

/** 포인트 반짝: 맑은 두 음(미→시) */
function points(): Buf {
  const len = seconds(0.6);
  const bell = (f: number) =>
    add(
      osc(len, () => f, 1),
      osc(len, () => f * 2.01, 1),
      0.3,
    );
  // 6ms 어택으로 시작 클릭 방지
  const env = (tau: number) => (t: number) => Math.min(1, t / 0.006) * Math.exp(-t / tau);
  const a = shape(bell(1318.5), env(0.12));
  const b = shape(bell(1975.5), env(0.25));
  return normalize(mix(len, [a, 0.8], [b, 1, 0.09]), 0.7);
}

/** 냠냠 와삭: 세 번 씹기 + 마지막 꿀꺽 */
function chomp(): Buf {
  const len = seconds(1.0);
  const bite = (seed: number) =>
    shape(
      biquad(biquad(noise(seconds(0.12), seed), 'bandpass', 900, 1.1), 'lowpass', 3000),
      (t) => Math.exp(-t / 0.03) * (1 + 0.5 * Math.sin(2 * Math.PI * 60 * t)),
    );
  const gulp = shape(
    osc(seconds(0.18), (t) => 260 - 500 * t, 3),
    (t) => Math.sin(Math.PI * Math.min(1, t / 0.18)) * 0.8,
  );
  return normalize(
    mix(len, [bite(11), 1, 0], [bite(12), 0.9, 0.2], [bite(13), 0.95, 0.4], [gulp, 0.7, 0.7]),
    0.8,
  );
}

export const SOUNDS: Record<string, () => Buf> = {
  'goat-bleat-1': () => bleat(410, 0.75, 1, 21),
  'goat-bleat-2': () => bleat(560, 0.55, 2, 22),
  'letter-open': letterOpen,
  stamp,
  points,
  chomp,
};
