// 시드 고정 결정적 난수. 같은 키는 언제나 같은 값을 준다(스케줄 재생성 시 동일 결과).

/** 문자열 → 32비트 해시 (cyrb53 변형) */
export function hash32(key: string): number {
  let h1 = 0xdeadbeef;
  let h2 = 0x41c6ce57;
  for (let i = 0; i < key.length; i++) {
    const ch = key.charCodeAt(i);
    h1 = Math.imul(h1 ^ ch, 2654435761);
    h2 = Math.imul(h2 ^ ch, 1597334677);
  }
  h1 = Math.imul(h1 ^ (h1 >>> 16), 2246822507) ^ Math.imul(h2 ^ (h2 >>> 13), 3266489909);
  h2 = Math.imul(h2 ^ (h2 >>> 16), 2246822507) ^ Math.imul(h1 ^ (h1 >>> 13), 3266489909);
  return (h2 >>> 0) ^ (h1 >>> 0);
}

/** 키에 대한 [0, 1) 난수 */
export function rand01(key: string): number {
  return (hash32(key) >>> 0) / 4294967296;
}

/** 키에 대한 [min, max] 정수 */
export function randInt(key: string, min: number, max: number): number {
  return min + Math.floor(rand01(key) * (max - min + 1));
}
