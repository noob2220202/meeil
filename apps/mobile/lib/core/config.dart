import 'package:flutter/foundation.dart';

/// 빌드 시 `--dart-define`으로 주입하는 설정. 키는 저장소에 넣지 않는다.
abstract final class AppConfig {
  /// 서버 주소. 기본값은 에뮬레이터에서 호스트 PC를 가리키는 주소.
  static const apiBaseUrl = String.fromEnvironment(
    'API_BASE_URL',
    defaultValue: 'http://10.0.2.2:3000',
  );

  static const kakaoNativeAppKey = String.fromEnvironment('KAKAO_NATIVE_APP_KEY');

  /// 구글 OAuth 웹 클라이언트 ID(서버가 ID 토큰 audience로 검증)
  static const googleServerClientId = String.fromEnvironment('GOOGLE_SERVER_CLIENT_ID');

  /// 개발용 로그인 버튼. 디버그 빌드에서만, 서버도 AUTH_DEV_LOGIN=true일 때만 동작.
  static const devLogin = kDebugMode && bool.fromEnvironment('DEV_LOGIN', defaultValue: true);

  static bool get kakaoEnabled => kakaoNativeAppKey.isNotEmpty;
  static bool get googleEnabled => googleServerClientId.isNotEmpty;
}
