import { createRemoteJWKSet, jwtVerify } from 'jose';
import { AppError } from '../errors.js';

/** 소셜 토큰 검증 결과. 이메일 등 다른 정보는 받지도 저장하지도 않는다. */
export interface SocialIdentity {
  providerUserId: string;
}

export interface SocialVerifier {
  kakao(accessToken: string): Promise<SocialIdentity>;
  google(idToken: string): Promise<SocialIdentity>;
}

const invalid = () => new AppError(401, 'SOCIAL_TOKEN_INVALID', '로그인 정보를 확인하지 못했어요.');

export function createSocialVerifier(opts: {
  kakaoAppId: string;
  googleClientIds: string[];
  fetchImpl?: typeof fetch;
}): SocialVerifier {
  const fetchImpl = opts.fetchImpl ?? fetch;
  const googleJwks = createRemoteJWKSet(new URL('https://www.googleapis.com/oauth2/v3/certs'));

  return {
    async kakao(accessToken) {
      if (!opts.kakaoAppId)
        throw new AppError(503, 'PROVIDER_DISABLED', '카카오 로그인 준비 중이에요.');
      // access_token_info: 토큰이 유효하고 우리 앱(app_id)에서 발급됐는지 확인
      const res = await fetchImpl('https://kapi.kakao.com/v1/user/access_token_info', {
        headers: { Authorization: `Bearer ${accessToken}` },
      });
      if (!res.ok) throw invalid();
      const body = (await res.json()) as { id?: number; app_id?: number };
      if (!body.id || String(body.app_id) !== opts.kakaoAppId) throw invalid();
      return { providerUserId: String(body.id) };
    },

    async google(idToken) {
      if (opts.googleClientIds.length === 0) {
        throw new AppError(503, 'PROVIDER_DISABLED', '구글 로그인 준비 중이에요.');
      }
      try {
        const { payload } = await jwtVerify(idToken, googleJwks, {
          issuer: ['accounts.google.com', 'https://accounts.google.com'],
          audience: opts.googleClientIds,
        });
        if (!payload.sub) throw invalid();
        return { providerUserId: payload.sub };
      } catch {
        throw invalid();
      }
    },
  };
}
