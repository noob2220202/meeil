import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api_client.dart';
import '../../core/config.dart';
import '../../core/token_store.dart';
import 'auth_api.dart';
import 'me.dart';
import 'social_login.dart';

sealed class SessionState {
  const SessionState();
}

/// 앱 시작 시 저장된 토큰으로 로그인 상태를 복원하는 중
class SessionRestoring extends SessionState {
  const SessionRestoring();
}

/// 저장된 토큰은 있지만 서버에 닿지 못함(오프라인 등). 다시 시도할 수 있다.
class SessionUnreachable extends SessionState {
  const SessionUnreachable(this.message);
  final String message;
}

class SignedOut extends SessionState {
  const SignedOut({this.underAge = false, this.notice});

  /// 만 14세 미만으로 가입이 거절됨 → 안내 화면
  final bool underAge;
  final String? notice;
}

class SignedIn extends SessionState {
  const SignedIn(this.me);
  final Me me;
}

final tokenStoreProvider = Provider<TokenStore>((ref) => SecureTokenStore());
final socialLoginProvider = Provider<SocialLogin>((ref) => SdkSocialLogin());

final apiClientProvider = Provider<ApiClient>((ref) {
  final client = ApiClient(
    baseUrl: AppConfig.apiBaseUrl,
    tokenStore: ref.watch(tokenStoreProvider),
  );
  client.onSessionExpired = () => ref.read(sessionProvider.notifier).expired();
  return client;
});

final authApiProvider = Provider<AuthApi>((ref) => AuthApi(ref.watch(apiClientProvider)));

class SessionController extends Notifier<SessionState> {
  AuthApi get _api => ref.read(authApiProvider);
  TokenStore get _store => ref.read(tokenStoreProvider);

  @override
  SessionState build() {
    Future.microtask(restore);
    return const SessionRestoring();
  }

  /// 저장된 토큰으로 로그인 유지(재실행 시)
  Future<void> restore() async {
    state = const SessionRestoring();
    if (await _store.read() == null) {
      state = const SignedOut();
      return;
    }
    try {
      state = SignedIn(await _api.me());
    } on ApiException catch (e) {
      if (e.statusCode == 401 || e.statusCode == 403) {
        await _store.clear();
        state = SignedOut(notice: e.statusCode == 403 ? e.message : null);
      } else {
        state = SessionUnreachable(e.message);
      }
    }
  }

  /// 소셜 로그인. 사용자가 취소하면 false. 실패는 ApiException으로 던진다.
  Future<bool> signIn(SocialProvider provider, {String? devId}) async {
    final social = ref.read(socialLoginProvider);
    final token = switch (provider) {
      SocialProvider.kakao => await social.kakaoAccessToken(),
      SocialProvider.google => await social.googleIdToken(),
      SocialProvider.dev => devId,
    };
    if (token == null) return false;
    final result = await _api.login(provider, token);
    await _store.write(result.tokens);
    state = SignedIn(result.me);
    return true;
  }

  /// 가입 단계 API 호출 후 갱신된 내 정보 반영
  void update(Me me) => state = SignedIn(me);

  /// 만 14세 미만: 서버가 계정을 지웠으므로 기기 토큰도 지우고 안내 화면으로
  Future<void> rejectUnderAge() async {
    await _store.clear();
    await ref.read(socialLoginProvider).signOutAll();
    state = const SignedOut(underAge: true);
  }

  /// 로그아웃 직전에 할 일(푸시 토큰 해제 등). 앱 계층에서 등록한다.
  Future<void> Function()? beforeSignOut;

  Future<void> signOut() async {
    try {
      await beforeSignOut?.call();
    } catch (_) {}
    final tokens = await _store.read();
    if (tokens != null) await _api.logout(tokens.refreshToken);
    await _store.clear();
    await ref.read(socialLoginProvider).signOutAll();
    state = const SignedOut();
  }

  /// refresh까지 실패(다른 기기 탈취 감지·만료 등)
  void expired() {
    if (state is SignedIn) state = const SignedOut(notice: '로그인이 만료되었어요. 다시 로그인해 주세요.');
  }

  void clearNotice() {
    if (state is SignedOut) state = const SignedOut();
  }
}

final sessionProvider = NotifierProvider<SessionController, SessionState>(SessionController.new);
