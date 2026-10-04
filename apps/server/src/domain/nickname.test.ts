import { describe, expect, it } from 'vitest';
import { checkNickname, nicknameChangeableAt, nicknameKey } from './nickname.js';

describe('checkNickname', () => {
  it.each(['메롱', '염소편지꾼', 'goat99', 'Abc가나다123'])('허용: %s', (n) => {
    expect(checkNickname(n)).toBeNull();
  });
  it('길이 2~10자', () => {
    expect(checkNickname('가')).toBe('LENGTH');
    expect(checkNickname('가나다라마바사아자차카')).toBe('LENGTH');
    expect(checkNickname('  가나  ')).toBeNull();
  });
  it('기호·공백·자모 단독 불가', () => {
    expect(checkNickname('가 나')).toBe('CHARS');
    expect(checkNickname('ㅋㅋㅋ')).toBe('CHARS');
    expect(checkNickname('hi!')).toBe('CHARS');
  });
  it('금칙어는 숫자를 끼워도 걸린다', () => {
    expect(checkNickname('시발염소')).toBe('BANNED');
    expect(checkNickname('시1발')).toBe('BANNED');
    expect(checkNickname('FuckYou')).toBe('BANNED');
  });
  it('운영자 사칭 불가', () => {
    expect(checkNickname('메에일관리자')).toBe('RESERVED');
    expect(checkNickname('Admin1')).toBe('RESERVED');
  });
});

describe('nicknameKey', () => {
  it('대소문자와 유니코드 정규화를 무시한다', () => {
    expect(nicknameKey('Goat')).toBe(nicknameKey('gOAT'));
    // NFD(조합형) 입력도 같은 키
    expect(nicknameKey('메롱'.normalize('NFD'))).toBe(nicknameKey('메롱'));
  });
});

describe('nicknameChangeableAt', () => {
  it('처음은 제한 없음, 이후 30일 뒤', () => {
    expect(nicknameChangeableAt(null)).toBeNull();
    expect(nicknameChangeableAt(new Date('2026-01-01T00:00:00Z'))?.toISOString()).toBe(
      '2026-01-31T00:00:00.000Z',
    );
  });
});
