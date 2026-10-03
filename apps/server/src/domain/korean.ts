// 한국어 조사 (앱 lib/core/korean.dart와 같은 규칙)

export function hasBatchim(word: string): boolean {
  const last = [...word].pop();
  if (!last) return false;
  const c = last.codePointAt(0)!;
  if (c >= 0xac00 && c <= 0xd7a3) return (c - 0xac00) % 28 !== 0;
  // 숫자: 0 1 3 6 7 8 은 받침 있음(영, 일, 삼, 육, 칠, 팔)
  return '013678'.includes(last);
}

/** 이/가 */
export const iGa = (word: string) => `${word}${hasBatchim(word) ? '이' : '가'}`;
