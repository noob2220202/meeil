import '../core/app_flags.dart';
import '../features/auth/session.dart';

abstract final class Routes {
  static const splash = '/splash';
  static const intro = '/intro';
  static const login = '/login';
  static const underAge = '/under-age';
  static const terms = '/signup/terms';
  static const birth = '/signup/birth';
  static const nickname = '/signup/nickname';
  static const permissions = '/signup/permissions';
  static const home = '/';

  /// 약관 본문(로그인 여부와 관계없이 열람 가능)
  static String doc(String id) => '/docs/$id';
}

/// 세션·플래그 상태로 가야 할 화면을 정한다. null이면 현재 위치 유지.
/// go_router redirect에서 쓰고, 단위 테스트로 흐름 전체를 검증한다.
String? resolveRedirect(SessionState session, AppFlags flags, String location) {
  if (location.startsWith('/docs/')) return null;

  String? goTo(String target) => location == target ? null : target;

  switch (session) {
    case SessionRestoring() || SessionUnreachable():
      return goTo(Routes.splash);
    case SignedOut(:final underAge):
      if (underAge) return goTo(Routes.underAge);
      if (!flags.introSeen) return goTo(Routes.intro);
      return goTo(Routes.login);
    case SignedIn(:final me):
      if (!me.termsAgreed) return goTo(Routes.terms);
      if (!me.birthDateSet) return goTo(Routes.birth);
      if (!me.nicknameSet) return goTo(Routes.nickname);
      if (!flags.permissionsIntroDone) return goTo(Routes.permissions);
      const preLogin = {
        Routes.splash,
        Routes.intro,
        Routes.login,
        Routes.underAge,
        Routes.terms,
        Routes.birth,
        Routes.nickname,
        Routes.permissions,
      };
      return preLogin.contains(location) ? Routes.home : null;
  }
}
