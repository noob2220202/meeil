import { describe, expect, it } from 'vitest';
import { createSocialVerifier } from './social.js';

const fakeFetch = (status: number, body: unknown) =>
  (async () => new Response(JSON.stringify(body), { status })) as typeof fetch;

describe('카카오 토큰 검증', () => {
  it('우리 앱에서 발급한 토큰만 통과', async () => {
    const ok = createSocialVerifier({
      kakaoAppId: '123',
      googleClientIds: [],
      fetchImpl: fakeFetch(200, { id: 987, app_id: 123 }),
    });
    await expect(ok.kakao('token-abcdefghij')).resolves.toEqual({ providerUserId: '987' });

    const otherApp = createSocialVerifier({
      kakaoAppId: '123',
      googleClientIds: [],
      fetchImpl: fakeFetch(200, { id: 987, app_id: 999 }),
    });
    await expect(otherApp.kakao('token-abcdefghij')).rejects.toMatchObject({
      code: 'SOCIAL_TOKEN_INVALID',
    });
  });

  it('만료 토큰(401)은 거부', async () => {
    const v = createSocialVerifier({
      kakaoAppId: '123',
      googleClientIds: [],
      fetchImpl: fakeFetch(401, { code: -401 }),
    });
    await expect(v.kakao('token-abcdefghij')).rejects.toMatchObject({ statusCode: 401 });
  });

  it('앱 ID 미설정이면 준비 중', async () => {
    const v = createSocialVerifier({ kakaoAppId: '', googleClientIds: [] });
    await expect(v.kakao('x')).rejects.toMatchObject({ code: 'PROVIDER_DISABLED' });
    await expect(v.google('x')).rejects.toMatchObject({ code: 'PROVIDER_DISABLED' });
  });

  it('구글: 서명이 맞지 않는 토큰은 거부', async () => {
    const v = createSocialVerifier({ kakaoAppId: '', googleClientIds: ['web-client'] });
    await expect(v.google('not.a.jwt')).rejects.toMatchObject({ code: 'SOCIAL_TOKEN_INVALID' });
  });
});
