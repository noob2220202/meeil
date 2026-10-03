// 편지지 (SPEC 7.2 [가정]). 종류 추가는 이 목록에 항목을 더하면 된다.

export interface StationeryDef {
  id: string;
  name: string;
  unlockHint: string;
  isDefault: boolean;
}

export const STATIONERY: readonly StationeryDef[] = [
  { id: 'cream', name: '크림', unlockHint: '가입하면 바로 받아요', isDefault: true },
  { id: 'lined', name: '줄노트', unlockHint: '출석 7일을 채우면 열려요', isDefault: false },
  { id: 'sky-cloud', name: '하늘 구름', unlockHint: '10개 시를 방문하면 열려요', isDefault: false },
];
