/**
 * 거의 안 바뀌는 조회(염소·지역 이름 등)를 프로세스 메모리에 잠깐 들고 있는다.
 * 같은 키를 동시에 부르면 DB 조회는 한 번만 한다. 실패는 캐시하지 않는다.
 */
export class TtlCache<V> {
  private readonly map = new Map<string, { value: Promise<V>; expires: number }>();

  constructor(
    private readonly ttlMs: number,
    private readonly clock: () => number = Date.now,
  ) {}

  get(key: string, load: () => Promise<V>): Promise<V> {
    const now = this.clock();
    const hit = this.map.get(key);
    if (hit && hit.expires > now) return hit.value;
    const value = load();
    this.map.set(key, { value, expires: now + this.ttlMs });
    value.catch(() => this.map.delete(key));
    return value;
  }

  clear(): void {
    this.map.clear();
  }
}
