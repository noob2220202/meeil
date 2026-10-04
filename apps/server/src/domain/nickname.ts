// 닉네임 규칙 (SPEC 8): 2~10자, 중복 불가, 금칙어 필터, 30일에 1회 변경

export const NICKNAME_MIN = 2;
export const NICKNAME_MAX = 10;
export const NICKNAME_CHANGE_DAYS = 30;

/** 완성형 한글·영문·숫자만. 자모 단독(ㅋㅋ)·공백·기호는 불가 */
const ALLOWED = /^[가-힣a-zA-Z0-9]+$/;

/** 운영자·공식 계정으로 오인될 수 있는 이름 */
const RESERVED = [
  '관리자',
  '운영자',
  '운영팀',
  '메에일',
  'meeil',
  '공식',
  'admin',
  'official',
  '우체국장',
  'gm',
];

/**
 * 금칙어(부분 일치). 우회를 막기 위해 숫자를 뺀 형태로도 검사한다.
 * 목록은 운영하며 늘린다.
 */
const BANNED = [
  '시발',
  '씨발',
  '씨바',
  '시바',
  'ㅅㅂ',
  '병신',
  '븅신',
  '좆',
  '존나',
  '졸라',
  '개새',
  '새끼',
  '미친',
  '닥쳐',
  '지랄',
  '염병',
  '애미',
  '애비',
  '느금',
  '섹스',
  '야동',
  '보지',
  '자지',
  '창녀',
  '걸레',
  'fuck',
  'shit',
  'bitch',
  'sex',
  'porn',
  'dick',
  'pussy',
  'nigger',
  'nazi',
];

export type NicknameProblem = 'LENGTH' | 'CHARS' | 'BANNED' | 'RESERVED';

export const NICKNAME_MESSAGES: Record<NicknameProblem | 'TAKEN' | 'TOO_SOON', string> = {
  LENGTH: `닉네임은 ${NICKNAME_MIN}~${NICKNAME_MAX}자로 지어 주세요.`,
  CHARS: '한글, 영문, 숫자만 쓸 수 있어요.',
  BANNED: '쓸 수 없는 단어가 들어 있어요.',
  RESERVED: '운영자로 오해받을 수 있는 이름은 쓸 수 없어요.',
  TAKEN: '이미 누군가 쓰고 있는 닉네임이에요.',
  TOO_SOON: `닉네임은 ${NICKNAME_CHANGE_DAYS}일에 한 번만 바꿀 수 있어요.`,
};

export function normalizeNickname(raw: string): string {
  return raw.normalize('NFC').trim();
}

/** 중복 검사 키: 대소문자 구분 없이 같은 이름은 하나만 */
export function nicknameKey(nickname: string): string {
  return normalizeNickname(nickname).toLowerCase();
}

export function checkNickname(raw: string): NicknameProblem | null {
  const nick = normalizeNickname(raw);
  const len = [...nick].length;
  if (len < NICKNAME_MIN || len > NICKNAME_MAX) return 'LENGTH';
  if (!ALLOWED.test(nick)) return 'CHARS';
  const lower = nick.toLowerCase();
  const stripped = lower.replace(/[0-9]/g, '');
  if (BANNED.some((w) => lower.includes(w) || stripped.includes(w))) return 'BANNED';
  if (RESERVED.some((w) => lower.includes(w))) return 'RESERVED';
  return null;
}

/** 다음 변경 가능 시각. 처음 정하는 경우는 언제든 가능(null). */
export function nicknameChangeableAt(changedAt: Date | null): Date | null {
  if (!changedAt) return null;
  return new Date(changedAt.getTime() + NICKNAME_CHANGE_DAYS * 24 * 60 * 60 * 1000);
}
