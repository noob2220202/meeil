// 보상형 광고 (SPEC 7.1): AdMob 서버측 검증(SSV) 콜백으로만 포인트를 준다.
// https://developers.google.com/admob/android/ssv
import { createPublicKey, verify, type KeyObject } from 'node:crypto';
import type { Db } from '../db.js';
import { POINTS, applyLedger, lockUser } from '../domain/points.js';
import { kstDayRange } from '../letters/rules.js';

export const ADMOB_KEYS_URL = 'https://www.gstatic.com/admob/reward/verifier-keys.json';
/** 콜백 시각이 이만큼 넘게 어긋나면 받지 않는다 */
const MAX_SKEW_MS = 24 * 60 * 60 * 1000;

/** 서명 검증 공개키 공급원(keyId → 키). 테스트에서는 직접 만든 키를 넣는다. */
export interface AdKeySource {
  get(keyId: string): Promise<KeyObject | null>;
}

/** 구글이 공개한 키 목록을 받아 하루 캐시한다. 모르는 keyId면 한 번 새로 받는다(최소 1분 간격). */
export class GoogleAdKeys implements AdKeySource {
  private keys = new Map<string, KeyObject>();
  private fetchedAt = 0;

  constructor(
    private readonly fetcher: (url: string) => Promise<{ json(): Promise<unknown> }> = fetch,
    private readonly clock: () => number = Date.now,
  ) {}

  private async refresh() {
    const res = (await (await this.fetcher(ADMOB_KEYS_URL)).json()) as {
      keys?: { keyId: number | string; pem: string }[];
    };
    const next = new Map<string, KeyObject>();
    for (const k of res.keys ?? []) next.set(String(k.keyId), createPublicKey(k.pem));
    if (next.size > 0) this.keys = next;
    this.fetchedAt = this.clock();
  }

  async get(keyId: string) {
    const age = this.clock() - this.fetchedAt;
    if (age > 24 * 3600_000 || (!this.keys.has(keyId) && age > 60_000)) await this.refresh();
    return this.keys.get(keyId) ?? null;
  }
}

export type SsvResult =
  | { ok: true; granted: boolean; reason?: 'DAILY_LIMIT' | 'DUPLICATE' }
  | {
      ok: false;
      error: 'BAD_SIGNATURE' | 'BAD_REQUEST' | 'STALE' | 'UNKNOWN_AD_UNIT' | 'UNKNOWN_USER';
    };

/**
 * 콜백 원본 쿼리스트링을 검증한다. 서명 대상은 signature 앞까지의 원문 그대로다
 * (signature, key_id는 항상 마지막에 온다).
 */
export async function verifySsv(
  rawQuery: string,
  keys: AdKeySource,
): Promise<URLSearchParams | null> {
  const i = rawQuery.indexOf('&signature=');
  if (i < 0) return null;
  const message = rawQuery.slice(0, i);
  const params = new URLSearchParams(rawQuery);
  const signature = params.get('signature');
  const keyId = params.get('key_id');
  if (!signature || !keyId) return null;
  const key = await keys.get(keyId);
  if (!key) return null;
  const ok = verify(
    'sha256',
    Buffer.from(message, 'utf8'),
    { key, dsaEncoding: 'der' },
    Buffer.from(signature, 'base64url'),
  );
  return ok ? params : null;
}

export class AdRewardService {
  constructor(
    private readonly db: Db,
    private readonly keys: AdKeySource,
    private readonly now: () => Date,
    /** 허용 광고 단위(비어 있으면 검사하지 않음) */
    private readonly adUnits: readonly string[] = [],
  ) {}

  async handleCallback(rawQuery: string): Promise<SsvResult> {
    const params = await verifySsv(rawQuery, this.keys);
    if (!params) return { ok: false, error: 'BAD_SIGNATURE' };
    const tx = params.get('transaction_id');
    const userId = params.get('user_id');
    const ts = Number(params.get('timestamp'));
    if (!tx || !userId || !Number.isFinite(ts)) return { ok: false, error: 'BAD_REQUEST' };
    if (!/^[0-9a-f-]{36}$/i.test(userId)) return { ok: false, error: 'UNKNOWN_USER' };
    if (Math.abs(this.now().getTime() - ts) > MAX_SKEW_MS) return { ok: false, error: 'STALE' };
    const unit = params.get('ad_unit') ?? '';
    if (this.adUnits.length > 0 && !this.adUnits.some((u) => u.endsWith(unit) || u === unit)) {
      return { ok: false, error: 'UNKNOWN_AD_UNIT' };
    }
    const user = await this.db.user.findUnique({ where: { id: userId }, select: { id: true } });
    if (!user) return { ok: false, error: 'UNKNOWN_USER' };
    return this.grant(userId, `ad:${tx}`, tx);
  }

  /** 하루 상한 안에서 광고 보상 지급(같은 거래는 한 번만) */
  async grant(userId: string, idempotencyKey: string, refId?: string): Promise<SsvResult> {
    const { start, end } = kstDayRange(this.now());
    return this.db.$transaction(async (t) => {
      await lockUser(t, userId);
      if (await t.pointsLedger.findUnique({ where: { idempotencyKey } })) {
        return { ok: true as const, granted: false, reason: 'DUPLICATE' as const };
      }
      const today = await t.pointsLedger.count({
        where: { userId, reason: 'AD_REWARD', createdAt: { gte: start, lt: end } },
      });
      if (today >= POINTS.AD_DAILY_MAX) {
        return { ok: true as const, granted: false, reason: 'DAILY_LIMIT' as const };
      }
      await applyLedger(t, {
        userId,
        delta: POINTS.AD_REWARD,
        reason: 'AD_REWARD',
        idempotencyKey,
        at: this.now(),
        ...(refId ? { refId } : {}),
      });
      return { ok: true as const, granted: true };
    });
  }

  async status(userId: string) {
    const { start, end } = kstDayRange(this.now());
    const today = await this.db.pointsLedger.count({
      where: { userId, reason: 'AD_REWARD', createdAt: { gte: start, lt: end } },
    });
    return {
      rewardPoints: POINTS.AD_REWARD,
      dailyMax: POINTS.AD_DAILY_MAX,
      todayCount: today,
      remaining: Math.max(0, POINTS.AD_DAILY_MAX - today),
    };
  }
}
