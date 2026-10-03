// 업적 초안 (SPEC 7.3 [제안]). 보상 수치는 조정 가능.

export interface AchievementDef {
  id: string;
  name: string;
  description: string;
  rewardPoints: number;
  titleText?: string;
  unlocksStationeryId?: string;
}

export const ACHIEVEMENTS: readonly AchievementDef[] = [
  {
    id: 'first-letter',
    name: '첫 편지',
    description: '처음으로 편지를 맡겼어요',
    rewardPoints: 2,
    titleText: '새내기 편지꾼',
  },
  { id: 'first-reply', name: '첫 답장', description: '처음으로 답장을 보냈어요', rewardPoints: 2 },
  {
    id: 'first-rolling',
    name: '첫 롤링페이퍼',
    description: '롤링페이퍼에 처음 참여했어요',
    rewardPoints: 2,
  },
  {
    id: 'attend-7',
    name: '출석 7일',
    description: '7일 출석했어요',
    rewardPoints: 3,
    unlocksStationeryId: 'lined',
  },
  {
    id: 'attend-30',
    name: '출석 30일',
    description: '30일 출석했어요',
    rewardPoints: 5,
    titleText: '단골 손님',
  },
  {
    id: 'attend-100',
    name: '출석 100일',
    description: '100일 출석했어요',
    rewardPoints: 10,
    titleText: '염소 목장 주민',
  },
  {
    id: 'visit-province-3',
    name: '세 도 나들이',
    description: '3개 시도를 방문했어요',
    rewardPoints: 3,
  },
  {
    id: 'visit-province-all',
    name: '전국 일주',
    description: '모든 시도를 방문했어요',
    rewardPoints: 20,
    titleText: '방랑 염소',
  },
  {
    id: 'visit-city-10',
    name: '열 고을',
    description: '10개 시를 방문했어요',
    rewardPoints: 3,
    unlocksStationeryId: 'sky-cloud',
  },
  { id: 'visit-city-50', name: '쉰 고을', description: '50개 시를 방문했어요', rewardPoints: 10 },
  {
    id: 'visit-city-100',
    name: '백 고을',
    description: '100개 시를 방문했어요',
    rewardPoints: 20,
    titleText: '백리 염소',
  },
  {
    id: 'received-100',
    name: '편지 부자',
    description: '편지를 100통 받았어요',
    rewardPoints: 10,
    titleText: '편지 부자',
  },
  {
    id: 'meet-all-goats',
    name: '염소 친구',
    description: '배달 염소 12마리를 모두 만났어요',
    rewardPoints: 10,
    titleText: '염소 친구',
  },
  {
    id: 'midnight-letter',
    name: '한밤의 편지',
    description: '0~4시에 편지를 맡겼어요',
    rewardPoints: 2,
    titleText: '올빼미',
  },
  { id: 'photo-letter', name: '찰칵', description: '사진 편지를 보냈어요', rewardPoints: 2 },
  {
    id: 'rolling-10',
    name: '두루마리 단골',
    description: '롤링페이퍼에 10번 참여했어요',
    rewardPoints: 5,
  },
  { id: 'visit-jeju', name: '제주 도착', description: '제주를 방문했어요', rewardPoints: 3 },
  {
    id: 'visit-ulleung',
    name: '울릉 도착',
    description: '울릉도를 방문했어요',
    rewardPoints: 5,
    titleText: '섬 염소',
  },
  {
    id: 'pen-pal-5',
    name: '단짝',
    description: '같은 친구와 5번 주고받았어요',
    rewardPoints: 5,
    titleText: '단짝',
  },
];
