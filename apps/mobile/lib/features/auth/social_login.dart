import 'package:flutter/services.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:kakao_flutter_sdk_user/kakao_flutter_sdk_user.dart';

import '../../core/api_client.dart';
import '../../core/config.dart';

/// 소셜 SDK로 토큰을 얻는다. 사용자가 취소하면 null.
abstract class SocialLogin {
  Future<String?> kakaoAccessToken();
  Future<String?> googleIdToken();
  Future<void> signOutAll();
}

class SdkSocialLogin implements SocialLogin {
  bool _googleReady = false;

  static void initKakao() {
    if (AppConfig.kakaoEnabled) KakaoSdk.init(nativeAppKey: AppConfig.kakaoNativeAppKey);
  }

  @override
  Future<String?> kakaoAccessToken() async {
    if (!AppConfig.kakaoEnabled) {
      throw const ApiException('PROVIDER_DISABLED', '카카오 로그인 준비 중이에요.');
    }
    try {
      OAuthToken token;
      if (await isKakaoTalkInstalled()) {
        try {
          token = await UserApi.instance.loginWithKakaoTalk();
        } on PlatformException catch (e) {
          // 카카오톡에서 사용자가 취소한 경우는 계정 로그인으로 넘기지 않는다
          if (e.code == 'CANCELED') return null;
          token = await UserApi.instance.loginWithKakaoAccount();
        }
      } else {
        token = await UserApi.instance.loginWithKakaoAccount();
      }
      return token.accessToken;
    } on PlatformException catch (e) {
      if (e.code == 'CANCELED') return null;
      throw const ApiException('SOCIAL_FAILED', '카카오 로그인에 실패했어요. 다시 시도해 주세요.');
    } on KakaoAuthException catch (e) {
      if (e.error == AuthErrorCause.accessDenied) return null;
      throw const ApiException('SOCIAL_FAILED', '카카오 로그인에 실패했어요. 다시 시도해 주세요.');
    } on KakaoException {
      throw const ApiException('SOCIAL_FAILED', '카카오 로그인에 실패했어요. 다시 시도해 주세요.');
    }
  }

  @override
  Future<String?> googleIdToken() async {
    if (!AppConfig.googleEnabled) {
      throw const ApiException('PROVIDER_DISABLED', '구글 로그인 준비 중이에요.');
    }
    final google = GoogleSignIn.instance;
    if (!_googleReady) {
      await google.initialize(serverClientId: AppConfig.googleServerClientId);
      _googleReady = true;
    }
    try {
      final account = await google.authenticate();
      return account.authentication.idToken;
    } on GoogleSignInException catch (e) {
      if (e.code == GoogleSignInExceptionCode.canceled) return null;
      throw const ApiException('SOCIAL_FAILED', '구글 로그인에 실패했어요. 다시 시도해 주세요.');
    }
  }

  @override
  Future<void> signOutAll() async {
    try {
      if (AppConfig.kakaoEnabled) await UserApi.instance.logout();
    } catch (_) {}
    try {
      if (_googleReady) await GoogleSignIn.instance.signOut();
    } catch (_) {}
  }
}
