/** 지연 시간 표본을 모아 백분위·오류율을 낸다 */
export class Histogram {
  private readonly samples: number[] = [];
  ok = 0;
  /** 4xx 중 업무상 정상(염소 없음, 이미 출석 등) */
  expected = 0;
  /** 5xx·네트워크 오류·예상 밖 4xx */
  errors = 0;
  readonly codes = new Map<number, number>();

  record(ms: number, status: number, expectedStatuses: readonly number[] = []): void {
    this.samples.push(ms);
    this.codes.set(status, (this.codes.get(status) ?? 0) + 1);
    if (status >= 200 && status < 300) this.ok++;
    else if (expectedStatuses.includes(status)) this.expected++;
    else this.errors++;
  }

  get count(): number {
    return this.samples.length;
  }

  percentile(p: number): number {
    if (this.samples.length === 0) return 0;
    const sorted = [...this.samples].sort((a, b) => a - b);
    const idx = Math.min(sorted.length - 1, Math.max(0, Math.ceil((p / 100) * sorted.length) - 1));
    return sorted[idx]!;
  }

  merge(other: Histogram): void {
    for (const s of other.samples) this.samples.push(s);
    this.ok += other.ok;
    this.expected += other.expected;
    this.errors += other.errors;
    for (const [c, n] of other.codes) this.codes.set(c, (this.codes.get(c) ?? 0) + n);
  }
}

export interface Thresholds {
  /** 전체 p95(ms) */
  p95: number;
  /** 전체 p99(ms) */
  p99: number;
  /** 오류율(0~1) */
  errorRate: number;
}

export const DEFAULT_THRESHOLDS: Thresholds = { p95: 300, p99: 800, errorRate: 0.001 };

/** 기준을 넘은 항목을 사람이 읽을 문장으로 돌려준다(없으면 빈 배열 = 통과) */
export function judge(total: Histogram, t: Thresholds = DEFAULT_THRESHOLDS): string[] {
  const fails: string[] = [];
  if (total.count === 0) return ['요청이 하나도 없었어요'];
  const p95 = total.percentile(95);
  const p99 = total.percentile(99);
  const rate = total.errors / total.count;
  if (p95 > t.p95) fails.push(`p95 ${p95.toFixed(0)}ms > ${t.p95}ms`);
  if (p99 > t.p99) fails.push(`p99 ${p99.toFixed(0)}ms > ${t.p99}ms`);
  if (rate > t.errorRate) fails.push(`오류율 ${(rate * 100).toFixed(2)}% > ${t.errorRate * 100}%`);
  return fails;
}
