import 'package:flutter/foundation.dart';

/// 빌드 시 `--dart-define`으로 주입하는 설정. 키는 저장소에 넣지 않는다.
abstract final class AppConfig {
  /// 서버 주소. 기본값은 에뮬레이터에서 호스트 PC를 가리키는 주소.
  static const apiBaseUrl = String.fromEnvironment(
    'API_BASE_URL',
    defaultValue: 'http://10.0.2.2:3000',
  );

  /// 약관·계정 삭제 웹 페이지 주소(기본은 API 서버와 같다)
  static const webBaseUrl = String.fromEnvironment('WEB_BASE_URL', defaultValue: apiBaseUrl);

  static const kakaoNativeAppKey = String.fromEnvironment('KAKAO_NATIVE_APP_KEY');

  /// 구글 OAuth 웹 클라이언트 ID(서버가 ID 토큰 audience로 검증)
  static const googleServerClientId = String.fromEnvironment('GOOGLE_SERVER_CLIENT_ID');

  /// 개발용 로그인 버튼. 디버그 빌드에서만, 서버도 AUTH_DEV_LOGIN=true일 때만 동작.
  static const devLogin = kDebugMode && bool.fromEnvironment('DEV_LOGIN', defaultValue: true);

  /// FCM(푸시). 넷 다 있어야 켜진다. 없으면 앱 안에서 1분마다 새 편지를 확인한다.
  static const firebaseApiKey = String.fromEnvironment('FIREBASE_API_KEY');
  static const firebaseAppId = String.fromEnvironment('FIREBASE_APP_ID');
  static const firebaseSenderId = String.fromEnvironment('FIREBASE_SENDER_ID');
  static const firebaseProjectId = String.fromEnvironment('FIREBASE_PROJECT_ID');

  static bool get pushEnabled =>
      firebaseApiKey.isNotEmpty &&
      firebaseAppId.isNotEmpty &&
      firebaseSenderId.isNotEmpty &&
      firebaseProjectId.isNotEmpty;

  /// 보상형 광고 단위. 기본값은 구글이 제공하는 테스트 광고(개발 중에는 테스트 광고만, CLAUDE.md).
  static const admobRewardedUnitId = String.fromEnvironment(
    'ADMOB_REWARDED_UNIT_ID',
    defaultValue: 'ca-app-pub-3940256099942544/5224354917',
  );

  static bool get kakaoEnabled => kakaoNativeAppKey.isNotEmpty;
  static bool get googleEnabled => googleServerClientId.isNotEmpty;
}
