// 염소 카탈로그 (SPEC 4.1, 4.2). 능력치는 스케줄 시뮬레이터(tools/schedule-sim)로 조정했다.
// 속도는 게임 속 km/h. 체류는 "희망 범위"이며, 실제 체류는 계획 단계에서
// 한 바퀴가 46시간 안에 끝나도록 줄어들 수 있다(src/schedule/plan.ts fitStays).

export interface DeliveryGoatDef {
  id: string;
  name: string;
  speedKmh: number;
  stayMinMin: number;
  stayMaxMin: number;
  hatColor: string;
  bagColor: string;
}

/** 배달 염소 12마리. 빠를수록 담당 구역이 넓고 체류가 짧다. */
export const DELIVERY_GOATS: readonly DeliveryGoatDef[] = [
  {
    id: 'merongi',
    name: '메롱이',
    speedKmh: 70,
    stayMinMin: 60,
    stayMaxMin: 100,
    hatColor: '#E8505B',
    bagColor: '#F6C177',
  },
  {
    id: 'eumme',
    name: '음메',
    speedKmh: 64,
    stayMinMin: 70,
    stayMaxMin: 110,
    hatColor: '#3D7DD8',
    bagColor: '#FFE08A',
  },
  {
    id: 'ppoyani',
    name: '뽀얀이',
    speedKmh: 58,
    stayMinMin: 80,
    stayMaxMin: 120,
    hatColor: '#F28DB2',
    bagColor: '#BDEBD7',
  },
  {
    id: 'kongi',
    name: '콩이',
    speedKmh: 50,
    stayMinMin: 90,
    stayMaxMin: 140,
    hatColor: '#5BAE6A',
    bagColor: '#FFC9D6',
  },
  {
    id: 'bori',
    name: '보리',
    speedKmh: 60,
    stayMinMin: 75,
    stayMaxMin: 115,
    hatColor: '#C9893B',
    bagColor: '#CDEBFF',
  },
  {
    id: 'dubu',
    name: '두부',
    speedKmh: 44,
    stayMinMin: 100,
    stayMaxMin: 150,
    hatColor: '#8C7AE6',
    bagColor: '#FFF1B8',
  },
  {
    id: 'mongsil',
    name: '몽실',
    speedKmh: 54,
    stayMinMin: 85,
    stayMaxMin: 125,
    hatColor: '#2BB3B1',
    bagColor: '#FFD8B5',
  },
  {
    id: 'gureum',
    name: '구름',
    speedKmh: 66,
    stayMinMin: 65,
    stayMaxMin: 105,
    hatColor: '#7FB3E6',
    bagColor: '#F5B7C5',
  },
  {
    id: 'uyu',
    name: '우유',
    speedKmh: 46,
    stayMinMin: 95,
    stayMaxMin: 145,
    hatColor: '#F3A24B',
    bagColor: '#D7F0C2',
  },
  {
    id: 'chaltteok',
    name: '찰떡',
    speedKmh: 52,
    stayMinMin: 85,
    stayMaxMin: 130,
    hatColor: '#D46A9F',
    bagColor: '#E3E8FF',
  },
  {
    id: 'hodu',
    name: '호두',
    speedKmh: 56,
    stayMinMin: 80,
    stayMaxMin: 120,
    hatColor: '#8D5B3C',
    bagColor: '#FFE7A3',
  },
  {
    id: 'arong',
    name: '아롱',
    speedKmh: 48,
    stayMinMin: 90,
    stayMaxMin: 140,
    hatColor: '#4F9D8D',
    bagColor: '#FFCFE0',
  },
];

/** 롤링 염소 색 (SPEC 4.2): 전국 노랑(금), 도 민트, 시 분홍 */
export const ROLLING_COLORS = {
  NATION: { hat: '#F2B705', bag: '#FFE08A' },
  PROVINCE: { hat: '#3FBF9B', bag: '#BDEBD7' },
  CITY: { hat: '#F27BA0', bag: '#FFC9D6' },
} as const;

/** 롤링 염소 능력치: 전국은 일주일, 도는 3일 안에 담당 지역을 모두 돈다 */
export const ROLLING_STATS = {
  NATION: { speedKmh: 110, stayMinMin: 15, stayMaxMin: 25 },
  PROVINCE: { speedKmh: 40, stayMinMin: 40, stayMaxMin: 80 },
  CITY: { speedKmh: 4, stayMinMin: 1440, stayMaxMin: 1440 },
} as const;
