// 스티커 20종(SPEC 12.3) SVG 생성. 외부 이미지 없이 손으로 쓴 도형만 쓴다.
// 실행: pnpm --filter @meeil/tools-stickers build:stickers
import { mkdir, writeFile } from 'node:fs/promises';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';

const here = dirname(fileURLToPath(import.meta.url));
const repo = join(here, '..', '..', '..');
const SRC_DIR = join(repo, 'assets-src', 'svg', 'stickers');
const APP_DIR = join(repo, 'apps', 'mobile', 'assets', 'stickers');

const O = '#7A5C48'; // 외곽선
const W = 3.5; // 외곽선 굵기
/** 속성 문자열 'a="1" b="2"'를 기본값 위에 덮어써 중복 속성이 생기지 않게 한다 */
function attrs(base: Record<string, string>, extra: string): string {
  const merged = { ...base };
  for (const m of extra.matchAll(/([a-z-]+)="([^"]*)"/g)) merged[m[1]!] = m[2]!;
  return Object.entries(merged)
    .map(([k, v]) => `${k}="${v}"`)
    .join(' ');
}
const s = (fill: string, extra = '') =>
  attrs(
    {
      fill,
      stroke: O,
      'stroke-width': String(W),
      'stroke-linejoin': 'round',
      'stroke-linecap': 'round',
    },
    extra,
  );
const line = (extra = '') =>
  attrs(
    {
      fill: 'none',
      stroke: O,
      'stroke-width': String(W),
      'stroke-linecap': 'round',
      'stroke-linejoin': 'round',
    },
    extra,
  );

const heartPath = (cx: number, cy: number, r: number) =>
  `M${cx} ${cy + r * 0.95} C${cx - r * 1.6} ${cy - r * 0.1} ${cx - r * 0.9} ${cy - r * 1.35} ${cx} ${cy - r * 0.45} C${cx + r * 0.9} ${cy - r * 1.35} ${cx + r * 1.6} ${cy - r * 0.1} ${cx} ${cy + r * 0.95} Z`;

const starPath = (cx: number, cy: number, R: number, r: number) => {
  const pts: string[] = [];
  for (let i = 0; i < 10; i++) {
    const a = -Math.PI / 2 + (i * Math.PI) / 5;
    const rad = i % 2 === 0 ? R : r;
    pts.push(`${(cx + rad * Math.cos(a)).toFixed(1)} ${(cy + rad * Math.sin(a)).toFixed(1)}`);
  }
  return `M${pts.join(' L')} Z`;
};

/** 염소 얼굴 공통(귀·뿔·머리·볼). 표정만 바꾼다 */
const goatBase = (face: string) => `
  <g fill="none" stroke-linecap="round">
    <path d="M24 17 Q20 8 13 7" stroke="${O}" stroke-width="9"/>
    <path d="M40 17 Q44 8 51 7" stroke="${O}" stroke-width="9"/>
    <path d="M24 17 Q20 8 13 7" stroke="#F3E3C3" stroke-width="4"/>
    <path d="M40 17 Q44 8 51 7" stroke="#F3E3C3" stroke-width="4"/>
  </g>
  <ellipse cx="11" cy="33" rx="9" ry="5" transform="rotate(-20 11 33)" ${s('#FFFFFF')}/>
  <ellipse cx="53" cy="33" rx="9" ry="5" transform="rotate(20 53 33)" ${s('#FFFFFF')}/>
  <ellipse cx="11" cy="33" rx="5" ry="2.2" transform="rotate(-20 11 33)" fill="#FFC9D6"/>
  <ellipse cx="53" cy="33" rx="5" ry="2.2" transform="rotate(20 53 33)" fill="#FFC9D6"/>
  <circle cx="32" cy="35" r="20" ${s('#FFFFFF')}/>
  <ellipse cx="32" cy="45" rx="10" ry="6.5" fill="#FFF3E6"/>
  <ellipse cx="20" cy="42" rx="4.2" ry="2.6" fill="#FFB3C4"/>
  <ellipse cx="44" cy="42" rx="4.2" ry="2.6" fill="#FFB3C4"/>
  ${face}`;

const eyes = `<ellipse cx="25" cy="35" rx="3.2" ry="4" fill="#3B2A20"/><ellipse cx="39" cy="35" rx="3.2" ry="4" fill="#3B2A20"/><circle cx="26.2" cy="33.4" r="1.2" fill="#fff"/><circle cx="40.2" cy="33.4" r="1.2" fill="#fff"/>`;
const smile = `<path d="M28 45 Q30 48 32 45.5 Q34 48 36 45" ${line('stroke-width="2.6"')}/>`;

const STICKERS: Record<string, string> = {
  heart: `<path d="${heartPath(32, 33, 18)}" ${s('#FF8FAB')}/><path d="M21 25 Q23 21 27 21" ${line('stroke="#fff" stroke-width="3"')}/>`,
  star: `<path d="${starPath(32, 34, 25, 11.5)}" ${s('#FFE08A')}/><circle cx="27" cy="36" r="1.8" fill="${O}"/><circle cx="37" cy="36" r="1.8" fill="${O}"/><path d="M30 41 Q32 43 34 41" ${line('stroke-width="2.2"')}/>`,
  flower: `${[0, 72, 144, 216, 288]
    .map(
      (a) =>
        `<ellipse cx="32" cy="17" rx="9" ry="12" transform="rotate(${a} 32 33)" ${s('#FFC9D6')}/>`,
    )
    .join('')}<circle cx="32" cy="33" r="8.5" ${s('#FFE08A')}/>`,
  clover: `${[0, 90, 180, 270]
    .map(
      (a) => `<path d="${heartPath(32, 19, 10)}" transform="rotate(${a} 32 32)" ${s('#9BD9A7')}/>`,
    )
    .join('')}<path d="M32 33 Q38 46 44 56" ${line()}/>`,
  cloud: `<path d="M16 46 Q6 46 7 37 Q8 29 17 30 Q18 18 31 18 Q42 18 45 28 Q57 26 58 37 Q58 46 48 46 Z" ${s('#FFFFFF')}/><circle cx="26" cy="36" r="1.8" fill="${O}"/><circle cx="38" cy="36" r="1.8" fill="${O}"/><ellipse cx="22" cy="40" rx="3" ry="1.8" fill="#FFC9D6"/><ellipse cx="42" cy="40" rx="3" ry="1.8" fill="#FFC9D6"/>`,
  sun: `${Array.from({ length: 8 }, (_, i) => {
    const a = (i * Math.PI) / 4;
    return `<path d="M${(32 + 20 * Math.cos(a)).toFixed(1)} ${(32 + 20 * Math.sin(a)).toFixed(1)} L${(32 + 28 * Math.cos(a)).toFixed(1)} ${(32 + 28 * Math.sin(a)).toFixed(1)}" ${line('stroke-width="4.5"')}/>`;
  }).join(
    '',
  )}<circle cx="32" cy="32" r="15" ${s('#FFD45E')}/><circle cx="27" cy="31" r="1.8" fill="${O}"/><circle cx="37" cy="31" r="1.8" fill="${O}"/><path d="M28 37 Q32 40 36 37" ${line('stroke-width="2.4"')}/>`,
  moon: `<path d="M40 8 A25 25 0 1 0 56 44 A20 20 0 1 1 40 8 Z" ${s('#FFE08A')}/><path d="${starPath(48, 18, 6, 2.6)}" ${s('#FFFFFF', 'stroke-width="2.5"')}/>`,
  note: `<path d="M26 46 L26 16 L48 11 L48 41" ${line('stroke-width="4.5"')}/><path d="M26 16 L48 11 L48 19 L26 24 Z" ${s(O)}/><ellipse cx="20" cy="47" rx="8" ry="6.5" ${s('#D9CCF5')}/><ellipse cx="42" cy="42" rx="8" ry="6.5" ${s('#D9CCF5')}/>`,
  letter: `<rect x="7" y="15" width="50" height="35" rx="6" ${s('#FFF8EC')}/><path d="M9 18 L32 35 L55 18" ${s('#FFE9C9')}/><path d="${heartPath(32, 34, 6)}" ${s('#FF8FAB', 'stroke-width="2.5"')}/>`,
  gift: `<rect x="10" y="26" width="44" height="30" rx="5" ${s('#FFC9D6')}/><rect x="7" y="18" width="50" height="11" rx="4" ${s('#FF8FAB')}/><rect x="28" y="18" width="8" height="38" fill="#FFE08A" stroke="${O}" stroke-width="${W}"/><path d="M32 18 Q20 6 17 13 Q16 19 32 18 Q44 19 47 13 Q44 6 32 18 Z" ${s('#FFE08A')}/>`,
  ribbon: `<path d="M32 30 Q14 12 9 22 Q6 32 14 36 Q22 38 32 30 Z" ${s('#FF8FAB')}/><path d="M32 30 Q50 12 55 22 Q58 32 50 36 Q42 38 32 30 Z" ${s('#FF8FAB')}/><path d="M28 33 L20 54 L27 50 L31 56 L32 35 Z" ${s('#FF8FAB')}/><path d="M36 33 L44 54 L37 50 L33 56 L32 35 Z" ${s('#FF8FAB')}/><circle cx="32" cy="31" r="6" ${s('#FFC9D6')}/>`,
  rainbow: `${[
    ['#FF8FAB', 24],
    ['#FFE08A', 18],
    ['#9BD9A7', 12],
  ]
    .map(
      ([c, r]) =>
        `<path d="M${32 - Number(r)} 44 A${r} ${r} 0 0 1 ${32 + Number(r)} 44" fill="none" stroke="${O}" stroke-width="10" stroke-linecap="round"/><path d="M${32 - Number(r)} 44 A${r} ${r} 0 0 1 ${32 + Number(r)} 44" fill="none" stroke="${c}" stroke-width="5" stroke-linecap="round"/>`,
    )
    .join(
      '',
    )}<ellipse cx="10" cy="47" rx="8" ry="5.5" ${s('#FFFFFF')}/><ellipse cx="54" cy="47" rx="8" ry="5.5" ${s('#FFFFFF')}/>`,
  cherry: `<path d="M22 40 Q26 22 38 10 M44 42 Q42 24 38 10" ${line()}/><path d="M38 10 Q50 6 54 14 Q46 18 38 10 Z" ${s('#9BD9A7')}/><circle cx="21" cy="45" r="10" ${s('#FF6B81')}/><circle cx="44" cy="46" r="10" ${s('#FF6B81')}/><path d="M16 42 Q17 39 20 38" ${line('stroke="#fff" stroke-width="2.6"')}/><path d="M39 43 Q40 40 43 39" ${line('stroke="#fff" stroke-width="2.6"')}/>`,
  leaf: `<path d="M12 52 Q10 20 50 10 Q56 44 12 52 Z" ${s('#9BD9A7')}/><path d="M14 50 Q30 34 46 15" ${line('stroke-width="2.8"')}/>`,
  'goat-smile': goatBase(eyes + smile),
  'goat-love': goatBase(
    `<path d="${heartPath(25, 35, 4.4)}" fill="#FF6B81"/><path d="${heartPath(39, 35, 4.4)}" fill="#FF6B81"/>${smile}`,
  ),
  'goat-sleep': goatBase(
    `<path d="M21 36 Q25 39 29 36" ${line('stroke-width="2.6"')}/><path d="M35 36 Q39 39 43 36" ${line('stroke-width="2.6"')}/><path d="M30 46 Q32 47 34 46" ${line('stroke-width="2.4"')}/><path d="M47 6 L55 6 L47 14 L55 14" ${line('stroke-width="2.6"')}/><path d="M56 17 L61 17 L56 22 L61 22" ${line('stroke-width="2.2"')}/>`,
  ),
  'goat-wow': goatBase(
    `${eyes}<ellipse cx="32" cy="47" rx="3.2" ry="4" ${s('#FF8FAB', 'stroke-width="2.4"')}/>`,
  ),
  'goat-laugh': goatBase(
    `<path d="M21 37 Q25 32 29 37" ${line('stroke-width="2.8"')}/><path d="M35 37 Q39 32 43 37" ${line('stroke-width="2.8"')}/><path d="M26 44 Q32 53 38 44 Z" ${s('#FF8FAB', 'stroke-width="2.6"')}/>`,
  ),
  'goat-tear': goatBase(
    `${eyes}<path d="M38 41 Q35 46 38 49 Q41 46 38 41 Z" fill="#7FC4F0" stroke="${O}" stroke-width="1.6"/><path d="M28 47 Q32 44 36 47" ${line('stroke-width="2.6"')}/>`,
  ),
};

async function main() {
  await mkdir(SRC_DIR, { recursive: true });
  await mkdir(APP_DIR, { recursive: true });
  for (const [id, body] of Object.entries(STICKERS)) {
    const svg = `<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 64 64">${body}</svg>\n`;
    await writeFile(join(SRC_DIR, `${id}.svg`), svg);
    await writeFile(join(APP_DIR, `${id}.svg`), svg);
  }
  console.log(`스티커 ${Object.keys(STICKERS).length}종 → ${APP_DIR}`);
}

await main();
