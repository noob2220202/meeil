# CLAUDE.md — 메에일(가칭) 염소 우체부 편지 앱

## 먼저 읽을 것
- `SPEC.md`가 **단일 진실 공급원**이다. 작업 전에 해당 장을 읽는다.
- SPEC에 없는 판단은 [제안] 기본값 방향으로 진행하고 `docs/DECISIONS.md`에 한 줄(날짜·결정·이유)로 남긴다.
- 사용자에게 질문하지 않고 끝까지 진행한다. 되돌리기 어려운 결정(패키지명, 스토어 제출, 결제)만 멈춘다.

## 프로젝트 한 줄
대한민국 일러스트 지도 위를 우체부 염소들이 돌며 편지를 배달하는 Android 앱(Flutter) + 서버(Node/TS) + 관리자 웹(React).

## 폴더 구조
```
apps/mobile   Flutter 앱 (Android 전용)
apps/server   Fastify + Prisma + PostgreSQL
apps/admin    React + Vite 관리자 SPA
tools/        에셋 생성 스크립트, 경계 데이터 가공, 스케줄 시뮬레이터
assets-src/   원본 SVG/사운드 (최종 번들은 apps/mobile/assets)
docs/         DECISIONS.md, 개인정보처리방침/약관 초안, 스토어 문구
```
실행·테스트·빌드 명령은 M0에서 확정한 뒤 이 파일의 아래 "명령어" 섹션에 채운다.

## 지켜야 할 규칙
- 언어: 앱 UI·사용자 문구는 한국어. 코드 식별자는 영어. 주석은 필요한 곳에만 한국어 또는 영어.
- 서버는 TypeScript strict, 입력은 zod로 검증, 시크릿은 환경변수(`.env`는 커밋 금지, `.env.example`만 커밋).
- Flutter는 `flutter analyze` 경고 0, 서버는 lint·타입체크·테스트 통과 후에만 커밋.
- **위치**: 서버로 정밀 좌표를 보내거나 저장하지 않는다. 기기에서 시 판정 후 지역 코드와 시각만 전송한다. 위치 권한은 대략적 위치(coarse) 포그라운드만.
- **에셋**: 외부 AI 이미지 생성 API를 쓰지 않는다. 캐릭터·UI는 직접 SVG로 만든다. 외부 자산(폰트·소리·데이터)은 라이선스가 명확할 때만 쓰고 `ASSETS_LICENSES.md`에 출처·라이선스·URL을 기록한다.
- **포인트·광고 보상**은 서버 원장이 권위. 광고 보상은 AdMob 서버측 검증으로만 지급.
- 모든 편지는 기명이다. 소셜 이메일·ID·생년월일은 어떤 API 응답에도 노출하지 않는다.
- 사진은 서버에서 EXIF 제거·리사이즈·WebP 변환 후 비공개 R2에 저장, 서명 URL로만 제공.
- 개발 중 광고는 테스트 광고 ID만 사용한다.

## 작업 방식
- SPEC 13장 마일스톤(M0→M9) 순서대로 연속 진행한다. 각 단계 종료 시 테스트 통과·앱 실행 확인·커밋·태그(`m0`…`m9`) 후 다음으로 간다.
- 염소 스케줄 생성기는 시뮬레이터 테스트(30일치, "모든 시는 48시간 안에 방문, 도착 하드캡 72시간")를 CI에 포함한다. 이 테스트가 깨지면 다음 단계로 가지 않는다.
- 염소 애니메이션과 지도는 실기기(Galaxy) 프레임으로 확인한다. 12~30마리 동시 렌더링에서 끊기지 않게 한다.
- UI 변경 후에는 스크린샷으로 직접 눈으로 확인한다. 귀여움이 이 앱의 핵심이므로 뒤뚱 모션·색·여백은 대충 넘기지 않는다.
- 큰 파일은 뼈대 → 내용 순으로 나눠 작성한다.

## 완료의 정의
기능이 동작하고, 테스트가 있고, 오류·빈 상태·로딩 상태 화면이 있고, SPEC의 해당 규칙과 일치하며, 관련 문서가 갱신된 상태.

## 명령어
사전 준비: Node 22 + pnpm 10, Docker, Flutter 3.47.6(stable) + Android SDK 36.
- 의존성 설치: `pnpm install` (루트) · `cd apps/mobile && flutter pub get`
- DB 기동: `docker compose up -d postgres` (최초 1회 `cp apps/server/.env.example apps/server/.env`)
- DB 마이그레이션·시드: `pnpm --filter @meeil/server db:deploy` · `pnpm --filter @meeil/server db:seed`
- 새 마이그레이션 만들기(비대화형): `mkdir apps/server/prisma/migrations/<YYYYMMDDHHMMSS>_<이름> && pnpm --filter @meeil/server -s db:diff > 그폴더/migration.sql` 후 `db:deploy`
- 서버 기동: `pnpm --filter @meeil/server dev` (http://localhost:3000/health)
- 서버 컨테이너(배포 형태): `docker compose --profile full up -d --build`
- 서버 테스트: `pnpm --filter @meeil/server test` (실제 PostgreSQL 필요. `<DB명>_test` DB를 자동으로 만들어 쓰므로 개발 데이터는 안전)
- 전체 점검(lint·타입·테스트·포맷): `pnpm lint && pnpm typecheck && pnpm test && pnpm format:check`
- 관리자 웹: `pnpm --filter @meeil/admin dev` (http://localhost:5173/admin/)
- 관리자 계정 만들기: `ADMIN_PASSWORD=... pnpm --filter @meeil/server admin:create <아이디> [ADMIN|MODERATOR]` (TOTP URI 출력, 배포는 `docs/ADMIN.md`)
- 지역 데이터 재생성: `pnpm --filter @meeil/tools-regions build:regions`
- 스티커 SVG 재생성: `pnpm --filter @meeil/tools-stickers build:stickers`
- 효과음 재생성(합성): `pnpm --filter @meeil/tools-sounds build:sounds`
- 스케줄 시뮬레이터: `pnpm --filter @meeil/tools-schedule-sim sim [--days 30] [--start 2026-10-01]` (CI에서도 실행, 제약 위반 시 실패. 같은 검증이 서버 테스트 `src/schedule/schedule.sim.test.ts`에도 있다)
- 앱 스케줄 픽스처 갱신: `pnpm --filter @meeil/tools-schedule-sim fixture ../../apps/mobile/test/fixtures/schedule_20261003_1200kst.json`
- 앱 실행(Galaxy): `cd apps/mobile && flutter run --dart-define=API_BASE_URL=http://<PC LAN IP>:3000` (USB 디버깅 연결. 소셜 키는 `docs/SOCIAL_LOGIN.md`, 푸시·R2는 `docs/PUSH_AND_STORAGE.md`)
- 앱 테스트: `cd apps/mobile && flutter analyze && flutter test --exclude-tags screenshot`
- 앱 스크린샷(Galaxy 해상도): `cd apps/mobile && flutter test --tags screenshot` → `build/screenshots/`
- 디버그 APK: `cd apps/mobile && flutter build apk --debug`
- 실기기 프레임 확인: `cd apps/mobile && flutter drive --profile --driver=test_driver/perf_driver.dart --target=integration_test/map_perf_test.dart [--dart-define=GOATS=60]` → `build/map_frames.timeline_summary.json` (기준은 `docs/PERFORMANCE.md`)
- 릴리스 AAB 빌드: (M8에서 서명 설정 후 추가)
