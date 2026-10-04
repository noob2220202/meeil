# 릴리스 빌드 (M8)

## 1. 업로드 키 만들기 — 한 번만, 직접

업로드 키는 **되돌리기 어려운 자산**이라 저장소나 이 작업 환경에서 만들지 않는다. 내 PC에서 만들고 안전한 곳(비밀번호 관리자 + 오프라인 백업)에 보관한다.

```bash
keytool -genkeypair -v -keystore ~/meeil-upload.jks -storetype PKCS12 \
  -keyalg RSA -keysize 2048 -validity 10000 -alias upload
```

`apps/mobile/android/key.properties`(커밋 금지, `.gitignore` 처리됨):

```properties
storeFile=/절대/경로/meeil-upload.jks
storePassword=...
keyAlias=upload
keyPassword=...
```

- Play Console에서 **Play 앱 서명**을 켠다(기본값). 앱 서명 키는 구글이 보관하고, 우리는 업로드 키로만 서명한다. 업로드 키를 잃어버려도 Play Console에서 재설정을 요청할 수 있다.
- `key.properties`가 없으면 릴리스 빌드는 안내 메시지와 함께 멈춘다(디버그 키로 서명된 릴리스가 나가지 않게).

## 2. 빌드

```bash
cd apps/mobile
flutter build appbundle --release \
  --dart-define=API_BASE_URL=https://api.<도메인> \
  --dart-define=KAKAO_NATIVE_APP_KEY=... \
  --dart-define=GOOGLE_SERVER_CLIENT_ID=... \
  --dart-define=FIREBASE_API_KEY=... --dart-define=FIREBASE_APP_ID=... \
  --dart-define=FIREBASE_SENDER_ID=... --dart-define=FIREBASE_PROJECT_ID=... \
  --dart-define=ADMOB_APP_ID=ca-app-pub-...~... \
  --dart-define=ADMOB_REWARDED_UNIT_ID=ca-app-pub-.../...
```

결과: `build/app/outputs/bundle/release/app-release.aab`

- 비공개 테스트 트랙까지는 광고 ID를 **테스트 ID(기본값)** 로 둔다(CLAUDE.md). 실제 광고 ID는 정식 출시 직전에만 넣는다.
- 버전: `pubspec.yaml`의 `version: 이름+코드`. 올릴 때마다 코드(+ 뒤 숫자)를 1 올린다.
- 서명 확인: `jarsigner -verify -verbose build/app/outputs/bundle/release/app-release.aab | tail -3`

## 3. 스토어 자료 다시 만들기

```bash
cd apps/mobile
flutter test --tags screenshot      # build/screenshots/
flutter test --tags store-assets    # 앱 아이콘·스플래시(android/res), docs/store/
```

등록 문구와 설문 답은 `docs/store/listing.md`.

## 4. 출시 전 확인 (SPEC 14)

- [ ] 개인정보처리방침·약관의 [운영자 이름]·[연락처]·[시행일]·[서버 호스팅 업체] 채우기 → `https://api.<도메인>/legal/privacy`, `/legal/terms`
- [ ] 계정 삭제 URL: `https://api.<도메인>/account/delete`
- [ ] 데이터 보안 양식, 콘텐츠 등급, 대상 연령(만 14세 이상) — `docs/store/listing.md`의 답
- [ ] 광고 ID 선언(예: 보상형 광고), 위치 권한 사용 설명, 알림 권한
- [ ] 개인 개발자 계정이면 비공개 테스트 요건(테스터 수·기간) 최신 정책 확인 — 전체 점검표는 `docs/CLOSED_TEST.md`
- [ ] 위치정보법상 신고 의무 해당 여부 확인(앱은 시 단위 코드만 서버로 보냄)
