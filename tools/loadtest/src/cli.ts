// 부하 테스트(M9). 가상 사용자 N명이 앱처럼 행동하며 엔드포인트별 지연·오류를 잰다.
// 사용: pnpm --filter @meeil/tools-loadtest load [--url http://localhost:3000] [--users 200] [--seconds 60]
// 서버는 AUTH_DEV_LOGIN=true(개발용 로그인)로 띄운다. 운영 서버에는 절대 돌리지 않는다.
import { randomUUID } from 'node:crypto';
import { writeFileSync } from 'node:fs';
import { DEFAULT_THRESHOLDS, Histogram, judge } from './stats.js';

function arg(name: string, fallback: string): string {
  const i = process.argv.indexOf(`--${name}`);
  return i > 0 && process.argv[i + 1] ? process.argv[i + 1]! : fallback;
}

const BASE = arg('url', 'http://localhost:3000').replace(/\/$/, '');
const USERS = Number(arg('users', '200'));
const SECONDS = Number(arg('seconds', '60'));
/** 한 사람이 요청 사이에 쉬는 평균 시간(ms). 실제 앱 사용보다 훨씬 빡빡하게 잡는다 */
const THINK_MS = Number(arg('think', '1000'));
const OUT = arg('out', '');

if (/meeil\.(app|kr|com)/.test(BASE)) {
  console.error('운영 도메인에는 부하 테스트를 돌리지 않아요.');
  process.exit(2);
}

const stats = new Map<string, Histogram>();
function hist(name: string): Histogram {
  let h = stats.get(name);
  if (!h) stats.set(name, (h = new Histogram()));
  return h;
}

interface Vu {
  ip: string;
  token: string;
  id: string;
  region: string;
}

async function request(
  vu: Pick<Vu, 'ip' | 'token'>,
  name: string,
  method: string,
  path: string,
  body?: unknown,
  expected: readonly number[] = [],
): Promise<{ status: number; json: unknown }> {
  const t0 = performance.now();
  let status = 0;
  let json: unknown = null;
  try {
    const res = await fetch(`${BASE}${path}`, {
      method,
      headers: {
        // 가상 사용자마다 다른 클라이언트 IP(서버는 프록시 1단 뒤라고 믿는다)
        'x-forwarded-for': vu.ip,
        ...(vu.token ? { authorization: `Bearer ${vu.token}` } : {}),
        ...(body !== undefined ? { 'content-type': 'application/json' } : {}),
      },
      body: body !== undefined ? JSON.stringify(body) : undefined,
      signal: AbortSignal.timeout(10_000),
    });
    status = res.status;
    const text = await res.text();
    json = text ? JSON.parse(text) : null;
  } catch {
    status = 599; // 네트워크 오류·시간 초과
  }
  hist(name).record(performance.now() - t0, status, expected);
  return { status, json };
}

function nickname(i: number): string {
  // 2~10자 영문·숫자. 실행마다·사용자마다 겹치지 않게(실행 ID 4자 + 번호)
  return `L${RUN.slice(-4)}${i}`.slice(0, 10);
}

async function signUp(i: number, placeIn: (i: number) => string): Promise<Vu> {
  const vu: Vu = {
    ip: `10.${(i >> 16) & 255}.${(i >> 8) & 255}.${i & 255}`,
    token: '',
    id: '',
    region: placeIn(i),
  };
  const login = await request(vu, 'POST /auth/dev', 'POST', '/auth/dev', {
    devId: `load-${RUN}-${i}`,
  });
  vu.token = (login.json as { accessToken: string }).accessToken;
  await request(vu, 'POST /me/agreements', 'POST', '/me/agreements', {
    terms: true,
    privacy: true,
  });
  await request(vu, 'POST /me/birthdate', 'POST', '/me/birthdate', { birthDate: '1995-05-05' });
  const me = await request(vu, 'PUT /me/nickname', 'PUT', '/me/nickname', {
    nickname: nickname(i),
  });
  vu.id = (me.json as { id: string }).id;
  await request(vu, 'POST /me/region', 'POST', '/me/region', { regionCode: vu.region });
  return vu;
}

/** 앱 사용 비율을 흉내 낸 행동들(가중치) */
function actions(vu: Vu, all: Vu[]): [number, () => Promise<unknown>][] {
  return [
    [15, () => request(vu, 'GET /letters/unread-count', 'GET', '/letters/unread-count')],
    [12, () => request(vu, 'GET /goats/schedule', 'GET', '/goats/schedule')],
    [12, () => request(vu, 'GET /letters/inbox', 'GET', '/letters/inbox')],
    [10, () => request(vu, 'GET /me', 'GET', '/me')],
    [10, () => request(vu, 'GET /rolling/current/all', 'GET', '/rolling/current/all')],
    [6, () => request(vu, 'GET /letters/sent', 'GET', '/letters/sent')],
    [5, () => request(vu, 'POST /me/region', 'POST', '/me/region', { regionCode: vu.region })],
    [5, () => request(vu, 'GET /attendance', 'GET', '/attendance')],
    [4, () => request(vu, 'GET /achievements', 'GET', '/achievements')],
    [4, () => request(vu, 'GET /users/search', 'GET', `/users/search?nick=L${RUN.slice(-4)}`)],
    [3, () => request(vu, 'GET /notices', 'GET', '/notices')],
    [3, () => request(vu, 'GET /points/history', 'GET', '/points/history')],
    [2, () => request(vu, 'POST /attendance', 'POST', '/attendance')],
    [
      4,
      () => {
        const to = all[Math.floor(Math.random() * all.length)]!;
        // 염소가 떠났으면 409(NO_GOAT_HERE), 포인트가 떨어지면 409, 자기 자신이면 400 — 업무상 정상
        return request(
          vu,
          'POST /letters',
          'POST',
          '/letters',
          {
            mode: 'DIRECT',
            recipientId: to.id,
            body: '부하 테스트 편지예요. 염소야 힘내!',
            stationeryId: 'cream',
            stickers: [],
            clientRequestId: randomUUID(),
          },
          [400, 409],
        );
      },
    ],
  ];
}

function pick<T>(weighted: [number, T][]): T {
  const total = weighted.reduce((s, [w]) => s + w, 0);
  let r = Math.random() * total;
  for (const [w, v] of weighted) if ((r -= w) < 0) return v;
  return weighted[weighted.length - 1]![1];
}

const sleep = (ms: number) => new Promise((r) => setTimeout(r, ms));
const RUN = Date.now().toString(36);

async function main() {
  const health = await fetch(`${BASE}/health`).catch(() => null);
  if (!health?.ok) {
    console.error(`서버에 닿지 않아요: ${BASE}/health`);
    process.exit(2);
  }
  const regionsRes = (await (await fetch(`${BASE}/regions`)).json()) as {
    regions: { code: string }[];
  };
  const regions = regionsRes.regions.map((r) => r.code);
  // 편지를 실제로 맡길 수 있게 절반은 지금 배달 염소가 머무는 시에 둔다
  const sched = (await (await fetch(`${BASE}/goats/schedule?hours=1`)).json()) as {
    serverTime: string;
    stops: { regionCode: string; arriveAt: string; departAt: string }[];
  };
  const now = sched.serverTime;
  const withGoat = [
    ...new Set(
      sched.stops.filter((s) => s.arriveAt <= now && s.departAt > now).map((s) => s.regionCode),
    ),
  ];
  const placeIn = (i: number) =>
    i % 2 === 0 && withGoat.length > 0
      ? withGoat[(i / 2) % withGoat.length]!
      : regions[i % regions.length]!;

  console.log(`가입 ${USERS}명 …`);
  const t0 = performance.now();
  const vus: Vu[] = [];
  for (let i = 0; i < USERS; i += 20) {
    const batch = await Promise.all(
      Array.from({ length: Math.min(20, USERS - i) }, (_, k) => signUp(i + k, placeIn)),
    );
    vus.push(...batch.filter((v) => v.token && v.id));
  }
  console.log(`가입 완료 ${vus.length}명 (${((performance.now() - t0) / 1000).toFixed(1)}s)`);
  if (vus.length < USERS * 0.99) {
    console.error('가입이 너무 많이 실패했어요.');
    process.exitCode = 1;
  }

  // 가입 단계 통계는 따로 두고, 본 부하만 판정한다
  const signupStats = new Map(stats);
  stats.clear();

  console.log(`부하 ${SECONDS}초, 생각 시간 평균 ${THINK_MS}ms …`);
  const end = Date.now() + SECONDS * 1000;
  const started = performance.now();
  await Promise.all(
    vus.map(async (vu) => {
      await sleep(Math.random() * THINK_MS); // 동시에 몰리지 않게 흩뿌린다
      const acts = actions(vu, vus);
      while (Date.now() < end) {
        await pick(acts)();
        await sleep(THINK_MS * (0.5 + Math.random()));
      }
    }),
  );
  const elapsed = (performance.now() - started) / 1000;

  const total = new Histogram();
  const rows = [...stats.entries()].sort((a, b) => b[1].count - a[1].count);
  const lines = [
    '| 엔드포인트 | 요청 | p50 | p95 | p99 | 업무4xx | 오류 |',
    '|---|---:|---:|---:|---:|---:|---:|',
  ];
  for (const [name, h] of rows) {
    total.merge(h);
    lines.push(
      `| ${name} | ${h.count} | ${h.percentile(50).toFixed(0)} | ${h.percentile(95).toFixed(0)} | ${h
        .percentile(99)
        .toFixed(0)} | ${h.expected} | ${h.errors} |`,
    );
  }
  lines.push(
    `| **전체** | **${total.count}** | **${total.percentile(50).toFixed(0)}** | **${total
      .percentile(95)
      .toFixed(
        0,
      )}** | **${total.percentile(99).toFixed(0)}** | ${total.expected} | **${total.errors}** |`,
  );
  const signup = new Histogram();
  for (const h of signupStats.values()) signup.merge(h);
  const fails = judge(total);
  const report = [
    `대상 ${BASE} · 가상 사용자 ${vus.length}명 · ${elapsed.toFixed(0)}초 · ${(total.count / elapsed).toFixed(0)} req/s`,
    `가입 단계: ${signup.count}요청, p95 ${signup.percentile(95).toFixed(0)}ms, 오류 ${signup.errors}`,
    '',
    ...lines,
    '',
    `기준: p95 ≤ ${DEFAULT_THRESHOLDS.p95}ms, p99 ≤ ${DEFAULT_THRESHOLDS.p99}ms, 오류율 ≤ ${DEFAULT_THRESHOLDS.errorRate * 100}%`,
    fails.length === 0 ? '결과: 통과' : `결과: 실패 — ${fails.join(', ')}`,
  ].join('\n');
  console.log(`\n${report}`);
  if (total.errors > 0) {
    const codes = [...total.codes.entries()].filter(([c]) => c >= 400);
    console.log('상태 코드:', Object.fromEntries(codes));
  }
  if (OUT) writeFileSync(OUT, `${report}\n`);
  if (fails.length > 0) process.exitCode = 1;
}

await main();
