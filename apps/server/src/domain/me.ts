import type { User } from '../generated/prisma/client.js';
import { nicknameChangeableAt } from './nickname.js';

/**
 * 내 정보 응답. 생년월일·소셜 ID·이메일은 절대 포함하지 않는다(CLAUDE.md 규칙).
 * 필드를 추가할 때는 반드시 이 함수에서 명시적으로 고른다.
 */
export function toMeDto(user: User) {
  const termsAgreed = Boolean(user.termsAgreedAt && user.privacyAgreedAt);
  const birthDateSet = user.birthDate !== null;
  const nicknameSet = user.nickname !== null;
  return {
    id: user.id,
    nickname: user.nickname,
    status: user.status,
    suspendedUntil: user.suspendedUntil?.toISOString() ?? null,
    pointsBalance: user.pointsBalance,
    randomReceive: user.randomReceive,
    notifyEnabled: user.notifyEnabled,
    homeRegionCode: user.homeRegionCode,
    lastRegionCode: user.lastRegionCode,
    nicknameChangeableAt: nicknameChangeableAt(user.nicknameChangedAt)?.toISOString() ?? null,
    onboarding: {
      termsAgreed,
      birthDateSet,
      nicknameSet,
      completed: termsAgreed && birthDateSet && nicknameSet,
    },
  };
}

export type MeDto = ReturnType<typeof toMeDto>;
