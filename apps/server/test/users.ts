// 테스트 공용: 가입을 마친 사용자 만들기·시계 옮기기
import type { FastifyInstance } from 'fastify';
import type { Db } from '../src/db.js';

export interface Res {
  statusCode: number;
  body: string;
  json: <T = any>() => T; // eslint-disable-line @typescript-eslint/no-explicit-any
}

export interface U {
  id: string;
  nickname: string;
  token: string;
  get: (url: string) => Promise<Res>;
  post: (url: string, payload?: object) => Promise<Res>;
  put: (url: string, payload?: object) => Promise<Res>;
  del: (url: string) => Promise<Res>;
}

export function userKit(
  app: () => FastifyInstance,
  db: () => Db,
  clock: { now: () => Date; set: (d: Date) => void },
) {
  async function loginToken(nickname: string) {
    const r = await app().inject({
      method: 'POST',
      url: '/auth/kakao',
      payload: { accessToken: `kakao-ok:${nickname}` },
    });
    return r.json<{ accessToken: string }>().accessToken;
  }

  async function placeAt(u: U, region: string) {
    await db().user.update({
      where: { id: u.id },
      data: { lastRegionCode: region, lastRegionReportedAt: clock.now() },
    });
  }

  async function makeUser(nickname: string, region = '11110'): Promise<U> {
    const auth = () => ({ authorization: `Bearer ${u.token}` });
    const u: U = {
      id: '',
      nickname,
      token: await loginToken(nickname),
      get: (url) => app().inject({ method: 'GET', url, headers: auth() }),
      post: (url, payload = {}) => app().inject({ method: 'POST', url, headers: auth(), payload }),
      put: (url, payload = {}) => app().inject({ method: 'PUT', url, headers: auth(), payload }),
      del: (url) => app().inject({ method: 'DELETE', url, headers: auth() }),
    };
    await u.post('/me/agreements', { terms: true, privacy: true });
    await u.post('/me/birthdate', { birthDate: '2000-01-01' });
    u.id = (await u.put('/me/nickname', { nickname })).json<{ id: string }>().id;
    await placeAt(u, region);
    return u;
  }

  async function jump(to: number | Date | string, ...users: U[]) {
    clock.set(new Date(to));
    for (const u of users) u.token = await loginToken(u.nickname);
  }

  return { makeUser, placeAt, jump, loginToken };
}
