import type { FastifyPluginAsync } from 'fastify';
import { z } from 'zod';
import type { SocialVerifier } from '../auth/social.js';
import { toMeDto } from '../domain/me.js';
import { AppError, parse } from '../errors.js';
import type { AuthProvider } from '../generated/prisma/client.js';

const Body = {
  kakao: z.object({ accessToken: z.string().min(10).max(4096) }),
  google: z.object({ idToken: z.string().min(10).max(8192) }),
  dev: z.object({ devId: z.string().regex(/^[a-zA-Z0-9_-]{1,40}$/) }),
  refresh: z.object({ refreshToken: z.string().min(10).max(200) }),
};

/** 개발용 로그인은 GOOGLE 공급자에 'dev:' 접두사 ID로 저장한다(별도 enum을 운영 DB에 두지 않기 위함). */
const DEV_PREFIX = 'dev:';

export const authRoutes: FastifyPluginAsync<{
  social: SocialVerifier;
  devLogin: boolean;
  rateLimit: boolean;
}> = async (app, { social, devLogin, rateLimit }) => {
  // 로그인 계열은 IP당 분당 20회
  const authLimit = rateLimit ? { config: { rateLimit: { max: 20, timeWindow: '1 minute' } } } : {};

  async function signIn(provider: AuthProvider, providerUserId: string) {
    const identity = await app.db.authIdentity.findUnique({
      where: { provider_providerUserId: { provider, providerUserId } },
      include: { user: true },
    });
    let user = identity?.user;
    let isNew = false;
    if (!user) {
      user = await app.db.user.create({
        data: { identities: { create: { provider, providerUserId } } },
      });
      isNew = true;
    }
    if (user.status === 'BANNED') throw new AppError(403, 'BANNED', '이용이 정지된 계정이에요.');
    await app.db.user.update({ where: { id: user.id }, data: { lastActiveAt: new Date() } });
    const tokens = await app.tokens.issue(user.id);
    return { ...tokens, isNew, me: toMeDto(user) };
  }

  app.post('/auth/kakao', authLimit, async (req) => {
    const { accessToken } = parse(Body.kakao, req.body);
    const { providerUserId } = await social.kakao(accessToken);
    return signIn('KAKAO', providerUserId);
  });

  app.post('/auth/google', authLimit, async (req) => {
    const { idToken } = parse(Body.google, req.body);
    const { providerUserId } = await social.google(idToken);
    return signIn('GOOGLE', providerUserId);
  });

  if (devLogin) {
    app.log.warn('개발용 로그인(/auth/dev)이 켜져 있습니다');
    app.post('/auth/dev', authLimit, async (req) => {
      const { devId } = parse(Body.dev, req.body);
      return signIn('GOOGLE', `${DEV_PREFIX}${devId}`);
    });
  }

  app.post('/auth/refresh', authLimit, async (req) => {
    const { refreshToken } = parse(Body.refresh, req.body);
    const { tokens } = await app.tokens.rotate(refreshToken);
    return tokens;
  });

  app.post('/auth/logout', async (req, reply) => {
    const { refreshToken } = parse(Body.refresh, req.body);
    await app.tokens.revoke(refreshToken);
    return reply.status(204).send();
  });
};
