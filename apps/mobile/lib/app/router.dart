import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../core/app_flags.dart';
import '../features/auth/session.dart';
import '../features/home/home_screen.dart';
import '../features/onboarding/birth_screen.dart';
import '../features/onboarding/doc_screen.dart';
import '../features/onboarding/intro_screen.dart';
import '../features/onboarding/login_screen.dart';
import '../features/onboarding/nickname_screen.dart';
import '../features/onboarding/permissions_screen.dart';
import '../features/onboarding/splash_screen.dart';
import '../features/onboarding/terms_screen.dart';
import '../features/onboarding/under_age_screen.dart';
import 'routes.dart';

final routerProvider = Provider<GoRouter>((ref) {
  // 세션·플래그가 바뀌면 redirect를 다시 계산
  final refresh = ValueNotifier(0);
  ref.listen(sessionProvider, (_, _) => refresh.value++);
  ref.listen(appFlagsProvider, (_, _) => refresh.value++);
  ref.onDispose(refresh.dispose);

  return GoRouter(
    initialLocation: Routes.splash,
    refreshListenable: refresh,
    redirect: (context, state) => resolveRedirect(
      ref.read(sessionProvider),
      ref.read(appFlagsProvider),
      state.matchedLocation,
    ),
    routes: [
      GoRoute(path: Routes.splash, builder: (_, _) => const SplashScreen()),
      GoRoute(path: Routes.intro, builder: (_, _) => const IntroScreen()),
      GoRoute(path: Routes.login, builder: (_, _) => const LoginScreen()),
      GoRoute(path: Routes.underAge, builder: (_, _) => const UnderAgeScreen()),
      GoRoute(path: Routes.terms, builder: (_, _) => const TermsScreen()),
      GoRoute(path: Routes.birth, builder: (_, _) => const BirthScreen()),
      GoRoute(path: Routes.nickname, builder: (_, _) => const NicknameScreen()),
      GoRoute(path: Routes.permissions, builder: (_, _) => const PermissionsScreen()),
      GoRoute(
        path: '/docs/:id',
        builder: (_, state) => DocScreen(docId: state.pathParameters['id']!),
      ),
      GoRoute(path: Routes.home, builder: (_, _) => const HomeScreen()),
    ],
  );
});
