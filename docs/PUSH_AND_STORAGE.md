# 푸시·사진 저장소 설정

키는 저장소에 넣지 않는다. 서버는 `apps/server/.env`, 앱은 `--dart-define`.

## 푸시(FCM HTTP v1)

1. Firebase 콘솔에서 프로젝트를 만들고 Android 앱(`com.meeil.app`)을 등록한다.
2. **서버**: 프로젝트 설정 → 서비스 계정 → 새 비공개 키(JSON). 그 안의 값을 넣는다.
   - `FCM_PROJECT_ID`, `FCM_CLIENT_EMAIL`, `FCM_PRIVATE_KEY`(줄바꿈은 `\n`)
   - 비워 두면 서버는 푸시를 로그로만 남긴다.
3. **앱**: 프로젝트 설정 → 내 앱(Android)의 값을 넣는다. `google-services.json`은 쓰지 않는다.
   ```
   --dart-define=FIREBASE_API_KEY=... --dart-define=FIREBASE_APP_ID=1:...:android:...
   --dart-define=FIREBASE_SENDER_ID=... --dart-define=FIREBASE_PROJECT_ID=...
   ```
   - 없으면 푸시 없이 동작하고, 편지함은 앱이 켜져 있는 동안 1분마다 새 편지를 확인한다.
4. 보내는 알림: 편지 도착(누르면 그 편지), 우리 동네에 배달 염소 도착(5분마다, 1인 6시간에 1번).

## 사진 저장소(Cloudflare R2)

1. R2 버킷을 **비공개**로 만든다(공개 접근·커스텀 도메인 없이).
2. API 토큰(객체 읽기·쓰기)을 만들고 서버 `.env`에:
   ```
   STORAGE_DRIVER=r2
   R2_ACCOUNT_ID=... R2_ACCESS_KEY_ID=... R2_SECRET_ACCESS_KEY=... R2_BUCKET=...
   ```
3. 앱에는 15분짜리 presigned URL만 내려간다.
4. 개발·테스트는 `STORAGE_DRIVER=local`(서버 디스크 + `/media` HMAC 서명 URL).
