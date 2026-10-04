# 보안 점검 (M9)

점검일 2026-10-04. ✅는 자동 테스트나 실제 확인으로 근거가 있는 항목, ⬜는 운영 키·콘솔이 필요해 출시 전에 사람이 할 일이다.
CI가 매 커밋 다시 확인하는 항목은 "근거"에 테스트 이름을 적었다.

## 1. 인증·권한

|     | 항목                                                                                                                            | 근거                                                                |
| --- | ------------------------------------------------------------------------------------------------------------------------------- | ------------------------------------------------------------------- |
| ✅  | 공개 목록에 없는 **모든 라우트는 토큰 없이 401**. 새 라우트를 만들고 인증을 빠뜨리면 테스트가 깨진다                            | `test/security.test.ts` "라우트 인증 목록"(등록된 라우트 81개 전수) |
| ✅  | 공개 라우트 17개는 이유와 함께 목록에 적어 둠(헬스·지역·스케줄·로그인·약관·계정 삭제 요청·AdMob 콜백·관리자 로그인·서명 미디어) | 같은 테스트의 `PUBLIC`                                              |
| ✅  | 다른 키로 서명한 토큰, `alg=none` 토큰, 만료(1시간) 토큰 거절                                                                   | "위조·만료·다른 용도 토큰"                                          |
| ✅  | 사용자 토큰으로 관리자 API, 관리자 토큰으로 사용자 API 불가(키·발급자 분리)                                                     | 같은 테스트                                                         |
| ✅  | 탈퇴·영구 정지 계정은 토큰이 살아 있어도 매 요청에서 막힘                                                                       | `auth/plugin.ts`(요청마다 상태 확인), `account.test.ts`             |
| ✅  | 관리자: scrypt 비밀번호 + TOTP(±30초), TOTP 시크릿은 AES-256-GCM 암호화 저장, 8시간 토큰, 모든 변경 감사 로그                   | `admin/crypto.test.ts`, `moderation.test.ts`                        |
| ✅  | refresh 토큰 회전·재사용 감지(재사용 시 전부 폐기)                                                                              | `auth.test.ts`                                                      |
| ✅  | 운영(`NODE_ENV=production`)에서 개발용 로그인(`AUTH_DEV_LOGIN`)을 켜면 서버가 부팅을 거부, `ADMIN_SECRET_KEY` 없으면 거부       | `env.test.ts`                                                       |

## 2. 개인정보·위치

|     | 항목                                                                                                                                  | 근거                                             |
| --- | ------------------------------------------------------------------------------------------------------------------------------------- | ------------------------------------------------ |
| ✅  | 사용자가 부를 수 있는 **모든 GET 응답**에 생년월일·소셜 ID·이메일·`provider`·좌표 키가 없음(실제 데이터를 채운 두 계정으로 전수 호출) | "개인정보 노출"                                  |
| ✅  | 관리자 화면 응답에도 생년월일·소셜 ID 없음(나이 확인 여부만)                                                                          | "관리자 화면 응답에도…"                          |
| ✅  | 지역 보고는 `regionCode`·`mocked`만 받는다. `lat`/`lng`가 섞이면 400(`.strict()`)                                                     | "위치 규칙"                                      |
| ✅  | DB의 사용자·지역 보고·방문 테이블에 좌표 칼럼이 없음                                                                                  | 같은 테스트 + `deploy/sql/integrity.sql`         |
| ✅  | 앱 권한은 `ACCESS_COARSE_LOCATION`(포그라운드)만. 합쳐진 매니페스트에 FINE·BACKGROUND 위치 없음                                       | `flutter build apk` 후 merged manifest 확인      |
| ✅  | 요청 로그에는 라우트 패턴만 남김(검색어·쿼리 문자열이 로그에 안 남음), Caddy 접속 로그에서 `Authorization`·`Cookie` 제거              | `app.ts` onResponse, `deploy/Caddyfile`          |
| ✅  | 사진: EXIF 제거·리사이즈·WebP, 비공개 버킷, 서명 URL(만료)                                                                            | `letters.test.ts` 사진 테스트                    |
| ✅  | DB 백업은 AES-256(PBKDF2 20만 회)으로 암호화해 사진과 다른 비공개 버킷에 보관. 틀린 암호로는 풀리지 않음                              | `deploy/backup.sh`, 리허설(`docs/OPERATIONS.md`) |

## 3. 입력·응답

|     | 항목                                                                                                                                                                                                      | 근거                                                    |
| --- | --------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | ------------------------------------------------------- |
| ✅  | 모든 입력은 zod 검증, 본문 64KB 제한(사진만 별도 한도)                                                                                                                                                    | 라우트 코드, `bodyLimit`                                |
| ✅  | 오류 응답에 스택·SQL·내부 경로 없음(500은 고정 문구)                                                                                                                                                      | "오류 응답에 내부 정보…"                                |
| ✅  | 보안 헤더: `nosniff`, `X-Frame-Options: DENY`, `Referrer-Policy: no-referrer`, COOP/CORP, `Permissions-Policy`, CSP(API는 `default-src 'none'`, HTML은 `script-src 'self'`), 운영 HSTS, JSON은 `no-store` | "보안 헤더", `lib/security-headers.ts`                  |
| ✅  | 공개 HTML(계정 삭제 페이지)에 인라인 스크립트 없음 — 스크립트를 파일로 분리해 CSP를 좁힘                                                                                                                  | 같은 테스트                                             |
| ✅  | 관리자 SPA: Caddy가 CSP·`X-Frame-Options`·`no-store` 부여. 실제 브라우저(Chromium)로 Caddy 뒤 로그인 화면을 열어 CSP 위반·오류 0 확인                                                                     | `deploy/Caddyfile`, 2026-10-04 운영 이미지 + Caddy 실측 |
| ✅  | 약관 마크다운 → HTML 변환은 HTML 이스케이프 후 처리                                                                                                                                                       | `legal/markdown.test.ts`                                |

## 4. 남용 방지

|     | 항목                                                                                                                                                                                 | 근거                                                                           |
| --- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------ | ------------------------------------------------------------------------------ |
| ✅  | 전역 요청 제한 120회/분/IP, 로그인·신고·계정 삭제 요청·크래시 보고는 더 좁게                                                                                                         | `app.ts`, 각 라우트                                                            |
| ✅  | **X-Forwarded-For 위조로 요청 제한을 피하지 못함**. 이전엔 `trustProxy: true`(가장 왼쪽 값을 믿음)라 헤더만 바꾸면 한도가 풀렸다 → 오른쪽 1단(Caddy)만 믿게 고침(`TRUST_PROXY_HOPS`) | "요청 제한 우회" + 운영 이미지·Caddy 앞단 실측(위조 헤더 125회 → 120회 뒤 429) |
| ✅  | 포인트는 서버 원장이 권위: 사용자별 advisory lock, 멱등 키, 잔액 = 원장 합계. 부하(7,500명 동시 가입·편지·출석) 뒤에도 정합성 위반 0                                                 | `rewards.test.ts`, `deploy/sql/integrity.sql`, `docs/LOADTEST.md`              |
| ✅  | 광고 보상은 AdMob SSV(ECDSA 서명) 검증으로만, 거래 ID 멱등, 하루 5회                                                                                                                 | `rewards.test.ts`                                                              |
| ✅  | 가짜 위치(isMocked)·비현실적 이동 거절                                                                                                                                               | `goats.test.ts`(지역 보고)                                                     |

## 5. 앱(Android)

|     | 항목                                                                                                                                                                | 근거                                                         |
| --- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------- | ------------------------------------------------------------ |
| ✅  | `allowBackup=false` + `dataExtractionRules`(클라우드 백업·기기 이전 모두 제외). 토큰은 Keystore 암호화라 다른 기기로 옮겨도 못 쓰고, 서버가 원장이라 백업할 게 없다 | `AndroidManifest.xml`, `res/xml/data_extraction_rules.xml`   |
| ✅  | 릴리스는 HTTPS만, 시스템 CA만 신뢰(사용자 설치 CA 불신). 평문 허용은 디버그 빌드 전용 리소스                                                                        | `res/xml/network_security_config.xml`, `src/debug/res/xml/…` |
| ✅  | 토큰은 `flutter_secure_storage`(Keystore), 생체 인증 권한은 매니페스트에서 제거                                                                                     | `core/token_store.dart`                                      |
| ✅  | 릴리스는 업로드 키 없으면 빌드 중단(디버그 서명 릴리스 방지)                                                                                                        | `build.gradle.kts`                                           |
| ✅  | 광고는 테스트 ID(비공개 테스트까지), 만 19세 미만은 미성년 광고 태그                                                                                                | `core/config.dart`, `me.ts`                                  |
| ✅  | 내보낸(exported) 컴포넌트: 런처 액티비티, 카카오 로그인 리다이렉트(SDK 요구), 라이브러리의 FCM 수신기뿐                                                             | merged manifest                                              |

## 6. 의존성·비밀값

|     | 항목                                                                                                                                                                                                     | 근거                                      |
| --- | -------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | ----------------------------------------- |
| ✅  | `pnpm audit --prod`: 알려진 취약점 0. prisma CLI가 끌어오던 `mysql2`(high·moderate)·`deepmerge-ts`(high)는 `pnpm-workspace.yaml` overrides로 패치 버전 고정(우리는 PostgreSQL만 써서 실행 경로엔 없었음) | CI `pnpm audit --prod --audit-level high` |
| ✅  | 저장소 비밀값 검사: AWS·구글 API 키·개인 키·GitHub·Slack 토큰 패턴 0건, `.env`·`key.properties`·`*.jks`·`google-services.json` 커밋 0건                                                                  | 2026-10-04 `git ls-files` 스캔            |
| ✅  | 시크릿은 환경변수만(`apps/server/.env.production`, 커밋 금지). `.env.example`에는 빈 값·개발용 값만                                                                                                      | `.gitignore`                              |

## 7. 출시 전 사람이 할 일

- ⬜ 운영 시크릿 새로 만들기: `JWT_SECRET`, `ADMIN_SECRET_KEY`, `MEDIA_SIGNING_SECRET`(로컬 저장소일 때), `BACKUP_PASSPHRASE` — 각각 `openssl rand -base64 48`. 비밀번호 관리자에 보관.
- ⬜ R2 API 토큰은 버킷 단위 최소 권한(사진 버킷: 읽기·쓰기, 백업 버킷: 쓰기·목록·삭제). 백업 버킷은 공개 접근 끔.
- ⬜ VPS: SSH 키 로그인만, 방화벽은 22·80·443만(5432·3000은 127.0.0.1 바인딩이라 외부 노출 없음), 자동 보안 업데이트.
- ⬜ 관리자 계정은 사람마다 따로(`admin:create`), TOTP 앱 등록, 퇴사·교체 시 즉시 재설정.
- ⬜ 실기기에서 실제 소셜 로그인·FCM·AdMob SSV 콜백 한 번씩 확인(이 환경에선 키가 없어 가짜로만 검증).
- ⬜ Play Console 데이터 보안 양식: `docs/store/listing.md`의 답(전송 중 암호화 예, 삭제 요청 가능 예, 대략적 위치 수집·서버 미전송 좌표 설명).

## 다시 점검하는 법

```bash
pnpm --filter @meeil/server test -- test/security.test.ts   # 인증·개인정보·헤더·위치·우회
pnpm audit --prod                                           # 의존성
cd apps/mobile && flutter build apk --debug && \
  grep -oE 'uses-permission[^/]*name="[^"]*"|allowBackup="[^"]*"' \
  build/app/intermediates/merged_manifests/debug/processDebugManifest/AndroidManifest.xml
```
