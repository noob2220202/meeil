// 염소 카탈로그 (SPEC 4.1, 4.2). 능력치는 M2 스케줄 시뮬레이터로 조정한다.

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
    speedKmh: 34,
    stayMinMin: 40,
    stayMaxMin: 70,
    hatColor: '#E8505B',
    bagColor: '#F6C177',
  },
  {
    id: 'eumme',
    name: '음메',
    speedKmh: 30,
    stayMinMin: 50,
    stayMaxMin: 80,
    hatColor: '#3D7DD8',
    bagColor: '#FFE08A',
  },
  {
    id: 'ppoyani',
    name: '뽀얀이',
    speedKmh: 26,
    stayMinMin: 60,
    stayMaxMin: 100,
    hatColor: '#F28DB2',
    bagColor: '#BDEBD7',
  },
  {
    id: 'kongi',
    name: '콩이',
    speedKmh: 22,
    stayMinMin: 70,
    stayMaxMin: 120,
    hatColor: '#5BAE6A',
    bagColor: '#FFC9D6',
  },
  {
    id: 'bori',
    name: '보리',
    speedKmh: 28,
    stayMinMin: 55,
    stayMaxMin: 90,
    hatColor: '#C9893B',
    bagColor: '#CDEBFF',
  },
  {
    id: 'dubu',
    name: '두부',
    speedKmh: 20,
    stayMinMin: 80,
    stayMaxMin: 130,
    hatColor: '#8C7AE6',
    bagColor: '#FFF1B8',
  },
  {
    id: 'mongsil',
    name: '몽실',
    speedKmh: 24,
    stayMinMin: 65,
    stayMaxMin: 110,
    hatColor: '#2BB3B1',
    bagColor: '#FFD8B5',
  },
  {
    id: 'gureum',
    name: '구름',
    speedKmh: 32,
    stayMinMin: 45,
    stayMaxMin: 75,
    hatColor: '#7FB3E6',
    bagColor: '#F5B7C5',
  },
  {
    id: 'uyu',
    name: '우유',
    speedKmh: 21,
    stayMinMin: 75,
    stayMaxMin: 125,
    hatColor: '#F3A24B',
    bagColor: '#D7F0C2',
  },
  {
    id: 'chaltteok',
    name: '찰떡',
    speedKmh: 25,
    stayMinMin: 60,
    stayMaxMin: 105,
    hatColor: '#D46A9F',
    bagColor: '#E3E8FF',
  },
  {
    id: 'hodu',
    name: '호두',
    speedKmh: 27,
    stayMinMin: 55,
    stayMaxMin: 95,
    hatColor: '#8D5B3C',
    bagColor: '#FFE7A3',
  },
  {
    id: 'arong',
    name: '아롱',
    speedKmh: 23,
    stayMinMin: 70,
    stayMaxMin: 115,
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
