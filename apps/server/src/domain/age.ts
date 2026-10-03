// 연령 판정 (SPEC 8): 만 14세 미만 가입 불가. 날짜 기준은 KST.

export const MIN_AGE = 14;
const KST_OFFSET_MS = 9 * 60 * 60 * 1000;

/** KST 기준 오늘 날짜 [년, 월, 일] */
export function kstToday(now: Date): [number, number, number] {
  const k = new Date(now.getTime() + KST_OFFSET_MS);
  return [k.getUTCFullYear(), k.getUTCMonth() + 1, k.getUTCDate()];
}

/** 'YYYY-MM-DD' → 만 나이. 생일 당일부터 한 살 더한다. */
export function ageOn(birth: string, now: Date): number {
  const [by, bm, bd] = birth.split('-').map(Number) as [number, number, number];
  const [y, m, d] = kstToday(now);
  let age = y - by;
  if (m < bm || (m === bm && d < bd)) age -= 1;
  return age;
}

/** 실존하는 날짜이고, 미래가 아니며, 120세 이하인지 */
export function isValidBirthDate(birth: string, now: Date): boolean {
  const m = /^(\d{4})-(\d{2})-(\d{2})$/.exec(birth);
  if (!m) return false;
  const [y, mo, d] = [Number(m[1]), Number(m[2]), Number(m[3])];
  const dt = new Date(Date.UTC(y, mo - 1, d));
  if (dt.getUTCFullYear() !== y || dt.getUTCMonth() !== mo - 1 || dt.getUTCDate() !== d)
    return false;
  const age = ageOn(birth, now);
  return age >= 0 && age <= 120;
}
