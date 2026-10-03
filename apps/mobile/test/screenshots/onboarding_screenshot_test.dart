@Tags(['screenshot'])
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:meeil/app/app.dart';
import 'package:meeil/app/theme.dart';
import 'package:meeil/core/token_store.dart';
import 'package:meeil/features/auth/auth_api.dart';
import 'package:meeil/features/home/home_screen.dart';
import 'package:meeil/features/onboarding/birth_screen.dart';
import 'package:meeil/features/onboarding/intro_screen.dart';
import 'package:meeil/features/onboarding/login_screen.dart';
import 'package:meeil/features/onboarding/nickname_screen.dart';
import 'package:meeil/features/onboarding/permissions_screen.dart';
import 'package:meeil/features/onboarding/splash_screen.dart';
import 'package:meeil/features/onboarding/terms_screen.dart';
import 'package:meeil/features/onboarding/under_age_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../support/fakes.dart';
import 'screenshot_helper.dart';

Future<Widget> wrap(Widget screen, {MemoryTokenStore? store, FakeBackend? backend}) async {
  final overrides = await appOverrides(
    backend: backend ?? FakeBackend(),
    store: store ?? MemoryTokenStore(),
  );
  return ProviderScope(
    overrides: overrides,
    child: MaterialApp(
      theme: buildTheme(),
      debugShowCheckedModeBanner: false,
      locale: appLocale,
      supportedLocales: const [appLocale],
      localizationsDelegates: appLocalizationsDelegates,
      home: screen,
    ),
  );
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({'flags.introSeen': true}));

  testWidgets('M1 화면들', (tester) async {
    await tester.runAsync(loadAppFonts);

    await captureScreen(tester, await wrap(const SplashScreen()), 'm1_01_splash');
    await captureScreen(tester, await wrap(const IntroScreen()), 'm1_02_intro1');
    await captureScreen(
      tester,
      await wrap(const IntroScreen()),
      'm1_03_intro3',
      beforeCapture: (t) async {
        await t.tap(find.text('다음'));
        await t.pumpAndSettle();
        await t.tap(find.text('다음'));
      },
    );
    await captureScreen(tester, await wrap(const LoginScreen()), 'm1_04_login');
    await captureScreen(
      tester,
      await wrap(const TermsScreen()),
      'm1_05_terms',
      beforeCapture: (t) => t.tap(find.text('(필수) 이용약관')),
    );
    await captureScreen(tester, await wrap(const BirthScreen()), 'm1_06_birth');

    // 닉네임 확인을 위해 로그인된 상태가 필요
    final backend = FakeBackend();
    final store = MemoryTokenStore()
      ..tokens = const Tokens(accessToken: 'access:none', refreshToken: 'r');
    final api = FakeAuthApi(backend, store);
    final login = await api.login(SocialProvider.kakao, 'shot');
    store.tokens = login.tokens;
    await captureScreen(
      tester,
      await wrap(const NicknameScreen(), store: store, backend: backend),
      'm1_07_nickname',
      beforeCapture: (t) async {
        await t.enterText(find.byType(TextField), '뽀얀염소');
        await t.pump(const Duration(milliseconds: 500));
      },
    );
    await captureScreen(
      tester,
      await wrap(const NicknameScreen(), store: store, backend: backend),
      'm1_08_nickname_taken',
      beforeCapture: (t) async {
        await t.enterText(find.byType(TextField), '메롱이');
        await t.pump(const Duration(milliseconds: 500));
      },
    );
    await captureScreen(tester, await wrap(const PermissionsScreen()), 'm1_09_permissions');
    await captureScreen(tester, await wrap(const UnderAgeScreen()), 'm1_10_under_age');
    await captureScreen(tester, await wrap(const HomeScreen()), 'm1_11_home');
  });
}
