# 소셜 로그인 설정

키는 저장소에 넣지 않는다. 서버는 `apps/server/.env`, 앱은 `--dart-define`으로 넣는다.

## 카카오

1. [Kakao Developers](https://developers.kakao.com)에서 애플리케이션 생성.
2. 플랫폼 → Android 등록: 패키지명 `com.meeil.app`, 키 해시(디버그·릴리스 각각).
   - 키 해시: `keytool -exportcert -alias androiddebugkey -keystore ~/.android/debug.keystore | openssl sha1 -binary | openssl base64` (비밀번호 `android`)
3. 카카오 로그인 활성화. 동의 항목은 **아무것도 필수로 받지 않는다**(고유 ID만 사용).
4. 값 넣기
   - 앱: `--dart-define=KAKAO_NATIVE_APP_KEY=<네이티브 앱 키>`
   - 서버: `KAKAO_APP_ID=<앱 ID(숫자)>`

## 구글

1. Google Cloud Console에서 OAuth 클라이언트 2개 생성
   - Android 클라이언트: 패키지명 `com.meeil.app` + SHA-1(디버그·릴리스)
   - 웹 클라이언트: 앱이 ID 토큰을 받을 때 쓰는 serverClientId
2. 값 넣기
   - 앱: `--dart-define=GOOGLE_SERVER_CLIENT_ID=<웹 클라이언트 ID>`
   - 서버: `GOOGLE_CLIENT_IDS=<웹 클라이언트 ID>`

## 키 없이 개발할 때

- 서버 `.env`에 `AUTH_DEV_LOGIN=true` (production에서는 서버가 기동을 거부한다)
- 앱 디버그 빌드의 "개발용 로그인" 버튼으로 테스트 계정 ID를 넣어 가입한다.
- 실제 기기에서 PC의 서버에 붙을 때: `--dart-define=API_BASE_URL=http://<PC의 LAN IP>:3000`
