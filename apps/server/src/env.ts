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
    /** 사진 저장소: local(개발·테스트) 또는 r2(운영, 비공개 버킷) */
    STORAGE_DRIVER: z.enum(['local', 'r2']).default('local'),
    LOCAL_STORAGE_DIR: z.string().default('./.storage'),
    /** 서명 URL을 만들 때 쓰는 이 서버의 바깥 주소(local 드라이버) */
    PUBLIC_BASE_URL: z.string().url().default('http://localhost:3000'),
    /** local 드라이버 서명 URL용 HMAC 키(32자 이상). 없으면 JWT_SECRET에서 파생 */
    MEDIA_SIGNING_SECRET: z.string().min(32).optional(),
    R2_ACCOUNT_ID: z.string().default(''),
    R2_ACCESS_KEY_ID: z.string().default(''),
    R2_SECRET_ACCESS_KEY: z.string().default(''),
    R2_BUCKET: z.string().default(''),
    /** FCM HTTP v1 서비스 계정. 비어 있으면 푸시는 로그로만 남긴다 */
    FCM_PROJECT_ID: z.string().default(''),
    FCM_CLIENT_EMAIL: z.string().default(''),
    /** PEM. 환경변수에서는 줄바꿈을 \\n으로 넣어도 된다 */
    FCM_PRIVATE_KEY: z.string().default(''),
    /** 관리자 TOTP 시크릿 암호화 키(32자 이상). production에서는 꼭 따로 둔다 */
    ADMIN_SECRET_KEY: z.preprocess(
      (v) => (v === '' ? undefined : v),
      z.string().min(32).optional(),
    ),
    /** 보상형 광고 단위 ID(SSV 콜백의 ad_unit 검사). 비어 있으면 검사하지 않는다 */
    ADMOB_AD_UNIT_IDS: csv,
    /** 배치 작업(pg-boss). 테스트에서는 끈다 */
    JOBS_ENABLED: z
      .enum(['true', 'false', '1', '0', ''])
      .default('true')
      .transform((v) => v !== 'false' && v !== '0'),
  })
  .refine(
    (e) =>
      e.STORAGE_DRIVER !== 'r2' ||
      Boolean(e.R2_ACCOUNT_ID && e.R2_ACCESS_KEY_ID && e.R2_SECRET_ACCESS_KEY && e.R2_BUCKET),
    { message: 'STORAGE_DRIVER=r2에는 R2_* 값이 모두 필요합니다', path: ['STORAGE_DRIVER'] },
  )
  .refine((e) => !(e.NODE_ENV === 'production' && !e.ADMIN_SECRET_KEY), {
    message: 'production에는 ADMIN_SECRET_KEY가 필요합니다',
    path: ['ADMIN_SECRET_KEY'],
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

/** TOTP 시크릿 암호화 키(개발에서는 JWT_SECRET에서 파생) */
export const adminSecretKey = (env: Env): string =>
  env.ADMIN_SECRET_KEY ?? `totp:${env.JWT_SECRET}`;
