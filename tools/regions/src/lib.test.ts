import { describe, expect, it } from 'vitest';
import {
  addIslandNeighbors,
  displayName,
  haversineKm,
  neighborsFromTopology,
  roundRing,
  toCity,
} from './lib.js';

describe('toCity', () => {
  it('일반구를 상위 시로 합친다', () => {
    expect(toCity('41111', '수원시장안구')).toEqual({ code: '41110', name: '수원시' });
    expect(toCity('41597', '화성시동탄구')).toEqual({ code: '41590', name: '화성시' });
  });
  it('자치구·군·시는 그대로 둔다', () => {
    expect(toCity('11110', '종로구')).toEqual({ code: '11110', name: '종로구' });
    expect(toCity('28177', '미추홀구')).toEqual({ code: '28177', name: '미추홀구' });
    expect(toCity('47940', '울릉군')).toEqual({ code: '47940', name: '울릉군' });
  });
});

describe('displayName', () => {
  it('시도 약칭을 붙인다', () => {
    expect(displayName('서울', '종로구')).toBe('서울 종로구');
    expect(displayName('세종', '세종시')).toBe('세종시');
  });
});

describe('neighborsFromTopology', () => {
  it('공유 arc로 이웃을 찾는다(음수 인덱스 포함)', () => {
    const n = neighborsFromTopology(
      [
        { arcs: [[0, 1]], properties: { code: 'A' } },
        { arcs: [[~1, 2]], properties: { code: 'B' } },
        { arcs: [[3]], properties: { code: 'C' } },
      ],
      'code',
    );
    expect(n.get('A')).toEqual(['B']);
    expect(n.get('B')).toEqual(['A']);
    expect(n.get('C')).toEqual([]);
  });
});

describe('addIslandNeighbors', () => {
  it('고립된 지역에 가까운 지역을 양방향으로 붙인다', () => {
    const n = addIslandNeighbors(
      new Map([
        ['A', ['B']],
        ['B', ['A']],
        ['I', []],
      ]),
      new Map<string, readonly [number, number]>([
        ['A', [127, 37]],
        ['B', [129, 37]],
        ['I', [127.1, 36.9]],
      ]),
      1,
    );
    expect(n.get('I')).toEqual(['A']);
    expect(n.get('A')).toEqual(['B', 'I']);
  });
});

describe('haversineKm', () => {
  it('서울-부산 직선거리 약 325km', () => {
    expect(haversineKm([126.978, 37.5665], [129.0756, 35.1796])).toBeGreaterThan(315);
    expect(haversineKm([126.978, 37.5665], [129.0756, 35.1796])).toBeLessThan(335);
  });
});

describe('roundRing', () => {
  it('소수 4자리 반올림 후 연속 중복점을 제거한다', () => {
    expect(
      roundRing([
        [127.00001, 37.00001],
        [127.00002, 37.00002],
        [127.1, 37.1],
      ]),
    ).toEqual([127, 37, 127.1, 37.1]);
  });
});
