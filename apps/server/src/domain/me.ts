import type { User } from '../generated/prisma/client.js';
import { ageOn } from './age.js';
import { nicknameChangeableAt } from './nickname.js';

/** 광고 요청에 미성년 설정을 적용하는 나이(만 19세 미만) */
const ADULT_AGE = 19;

/**
 * 내 정보 응답. 생년월일·소셜 ID·이메일은 절대 포함하지 않는다(CLAUDE.md 규칙).
 * 필드를 추가할 때는 반드시 이 함수에서 명시적으로 고른다.
 */
export function toMeDto(
  user: User & { titleAchievement?: { titleText: string | null } | null },
  now: Date = new Date(),
) {
  const termsAgreed = Boolean(user.termsAgreedAt && user.privacyAgreedAt);
  const birthDateSet = user.birthDate !== null;
  const nicknameSet = user.nickname !== null;
  return {
    id: user.id,
    nickname: user.nickname,
    status: user.status,
    suspendedUntil: user.suspendedUntil?.toISOString() ?? null,
    pointsBalance: user.pointsBalance,
    /** 닉네임 옆에 붙는 칭호 */
    title: user.titleAchievement?.titleText ?? null,
    titleAchievementId: user.titleAchievementId,
    /**
     * 광고 요청 설정. 생년월일 자체는 내보내지 않고, 미성년 여부만 본인에게 알려
     * 광고 SDK의 미성년 태그(tagForUnderAgeOfConsent)를 켜게 한다(SPEC 7.1).
     */
    ads: {
      underAge: user.birthDate
        ? ageOn(user.birthDate.toISOString().slice(0, 10), now) < ADULT_AGE
        : true,
    },
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
