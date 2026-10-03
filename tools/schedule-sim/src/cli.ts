// 염소 스케줄 시뮬레이터. 서버 스케줄 생성기를 그대로 돌려 제약과 통계를 보여 준다.
// 사용: pnpm --filter @meeil/tools-schedule-sim sim [--days 30] [--start 2026-10-01] [--letters 5000]
import { parseArgs } from 'node:util';
import {
  buildCatalogPlan,
  generateStops,
  routeTravelMinutes,
  TIME,
  verifySchedule,
} from '../../../apps/server/src/schedule/index.ts';

const { values } = parseArgs({
  options: {
    days: { type: 'string', default: '30' },
    start: { type: 'string', default: new Date().toISOString().slice(0, 10) },
    letters: { type: 'string', default: '5000' },
    seed: { type: 'string' },
  },
});

const days = Number(values.days);
const from = Date.parse(`${values.start}T00:00:00+09:00`);
const to = from + days * TIME.DAY;
const h = (min: number) => `${(min / 60).toFixed(1)}h`;

const t0 = performance.now();
const plan = buildCatalogPlan(values.seed);
const t1 = performance.now();
const stops = generateStops(plan, from, to);
const t2 = performance.now();
const report = verifySchedule(plan, stops, from, to, { letters: Number(values.letters) });

console.log(
  `\n🐐 메에일 염소 스케줄 시뮬레이션: ${values.start}부터 ${days}일 (시드 ${plan.seed})`,
);
console.log(
  `   계획 ${Math.round(t1 - t0)}ms · 정류 ${stops.length}개 생성 ${Math.round(t2 - t1)}ms\n`,
);
console.log('배달 염소  속도   담당  이동    체류(분)    최악 한 바퀴');
for (const r of plan.delivery) {
  const g = plan.goats.get(r.goatId)!;
  const travel = routeTravelMinutes(plan.regions, r.tour, g.speedKmh);
  console.log(
    `${r.goatId.padEnd(10)} ${String(g.speedKmh).padStart(3)}km/h ${String(r.tour.length).padStart(3)}곳 ${h(travel).padStart(6)}  ${`${r.stayMinMin}~${r.stayMaxMin}`.padStart(8)}  ${h(travel + r.tour.length * r.stayMaxMin).padStart(7)}`,
  );
}
console.log(
  `\n최장 빈 시간      ${h(report.maxEmptyGapMin)} (${report.worstGapRegion}) · 한도 48h`,
);
console.log(
  `편지 도착 시간     중앙 ${h(report.etaP50Min)} · 95% ${h(report.etaP95Min)} · 최대 ${h(report.etaMaxMin)} · 한도 72h`,
);
console.log(`특급 배달         ${report.expressCount} / ${report.lettersSimulated}통`);
console.log(
  `염소 체류 비율     지역 평균 ${(report.avgPresenceRatio * 100).toFixed(1)}% (편지를 맡길 수 있는 시간)`,
);
if (report.errors.length > 0) {
  console.log(`\n❌ 제약 위반 ${report.errors.length}건`);
  for (const e of report.errors.slice(0, 20)) console.log(`  - ${e}`);
  process.exit(1);
}
console.log('\n✅ 모든 제약 통과');
