import { z } from 'zod';

const csv = z
  .string()
  .default('')
  .transform((s) =>
    s
      .split(',')
      .map((o) => o.trim())
      .filter(Boolean),
  );

const bool = z
  .enum(['true', 'false', '1', '0', ''])
  .default('false')
  .transform((v) => v === 'true' || v === '1');

const EnvSchema = z
  .object({
    NODE_ENV: z.enum(['development', 'test', 'production']).default('development'),
    PORT: z.coerce.number().int().positive().default(3000),
    HOST: z.string().default('0.0.0.0'),
    DATABASE_URL: z.string().url(),
    CORS_ORIGINS: csv,
    /** 자체 access JWT 서명 키(HS256). 32자 이상 */
    JWT_SECRET: z.string().min(32),
    /** 카카오 앱 ID(숫자). 토큰이 우리 앱에서 발급됐는지 확인한다 */
    KAKAO_APP_ID: z.string().default(''),
    /** 구글 ID 토큰 audience로 허용할 OAuth 클라이언트 ID 목록 */
    GOOGLE_CLIENT_IDS: csv,
    /** 개발용 로그인(/auth/dev). production에서는 켤 수 없다 */
    AUTH_DEV_LOGIN: bool,
  })
  .refine((e) => !(e.NODE_ENV === 'production' && e.AUTH_DEV_LOGIN), {
    message: 'production에서는 AUTH_DEV_LOGIN을 켤 수 없습니다',
    path: ['AUTH_DEV_LOGIN'],
  });

export type Env = z.infer<typeof EnvSchema>;

export function loadEnv(source: NodeJS.ProcessEnv = process.env): Env {
  const parsed = EnvSchema.safeParse(source);
  if (!parsed.success) {
    throw new Error(`환경변수 오류: ${z.prettifyError(parsed.error)}`);
  }
  return parsed.data;
}
