import { describe, expect, it } from 'vitest';
import { loadEnv } from './env.js';

const base = {
  DATABASE_URL: 'postgresql://u:p@localhost:5432/db',
  JWT_SECRET: 'x'.repeat(32),
};

describe('loadEnv', () => {
  it('기본값을 채우고 목록 값을 나눈다', () => {
    const env = loadEnv({
      ...base,
      CORS_ORIGINS: 'http://a.test, http://b.test',
      GOOGLE_CLIENT_IDS: 'a,b',
    });
    expect(env.PORT).toBe(3000);
    expect(env.NODE_ENV).toBe('development');
    expect(env.CORS_ORIGINS).toEqual(['http://a.test', 'http://b.test']);
    expect(env.GOOGLE_CLIENT_IDS).toEqual(['a', 'b']);
    expect(env.AUTH_DEV_LOGIN).toBe(false);
  });

  it('필수값이 없거나 JWT 키가 짧으면 실패한다', () => {
    expect(() => loadEnv({})).toThrow(/환경변수 오류/);
    expect(() => loadEnv({ ...base, JWT_SECRET: 'short' })).toThrow(/환경변수 오류/);
  });

  it('production에서 개발용 로그인은 켤 수 없다', () => {
    expect(() => loadEnv({ ...base, NODE_ENV: 'production', AUTH_DEV_LOGIN: 'true' })).toThrow(
      /AUTH_DEV_LOGIN/,
    );
  });
});
