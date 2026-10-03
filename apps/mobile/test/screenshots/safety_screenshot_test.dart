@Tags(['screenshot'])
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:meeil/app/app.dart';
import 'package:meeil/app/theme.dart';
import 'package:meeil/core/token_store.dart';
import 'package:meeil/features/goats/hand_availability.dart';
import 'package:meeil/features/letters/letter_models.dart';
import 'package:meeil/features/letters/letter_screen.dart';
import 'package:meeil/features/map/goat_painter.dart';
import 'package:meeil/features/rolling/rolling_models.dart';
import 'package:meeil/features/rolling/rolling_paper_screen.dart';
import 'package:meeil/features/safety/goat_eating.dart';
import 'package:meeil/features/safety/settings_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../support/fakes.dart';
import 'screenshot_helper.dart';

Future<Widget> app(
  String initial, {
  Object? extra,
  void Function(FakeSafetyApi, FakeRollingApi)? setup,
}) async {
  SharedPreferences.setMockInitialValues({});
  final backend = FakeBackend();
  final store = MemoryTokenStore()..tokens = backend.signedUp('나');
  final safety = FakeSafetyApi(store, backend: backend);
  final rolling = FakeRollingApi(MemoryTokenStore());
  setup?.call(safety, rolling);
  final overrides = await appOverrides(
    backend: backend,
    store: store,
    safety: safety,
    rolling: rolling,
  );
  final router = GoRouter(
    initialLocation: '/',
    routes: [
      GoRoute(path: '/', builder: (_, _) => const Scaffold()),
      GoRoute(
        path: '/letters/:id',
        builder: (_, s) => LetterScreen(id: s.pathParameters['id']!, initial: s.extra as Letter?),
      ),
      GoRoute(
        path: '/rolling/:id',
        builder: (_, s) => RollingPaperScreen(id: s.pathParameters['id']!),
      ),
      GoRoute(path: '/settings', builder: (_, _) => const SettingsScreen()),
    ],
  );
  Future.microtask(() => router.push(initial, extra: extra));
  return ProviderScope(
    overrides: [...overrides, clockTickProvider.overrideWith(() => FixedClock(fixtureNow))],
    child: MaterialApp.router(
      theme: buildTheme(),
      debugShowCheckedModeBanner: false,
      locale: appLocale,
      supportedLocales: const [appLocale],
      localizationsDelegates: appLocalizationsDelegates,
      routerConfig: router,
    ),
  );
}

void main() {
  testWidgets('M6 신고·차단·먹기 화면들', (tester) async {
    await tester.runAsync(loadAppFonts);

    // 1) 먹는 연출 4컷
    const look = GoatLook(hat: Color(0xFFE8505B), bag: Color(0xFFF6C177));
    await captureScreen(
      tester,
      MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: buildTheme(),
        home: Scaffold(
          backgroundColor: Palette.cream,
          body: SafeArea(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                for (final p in [0.12, 0.45, 0.7, 1.0])
                  Container(
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(18),
                      border: Border.all(color: Palette.outline, width: 2),
                    ),
                    child: GoatEatingScene(look: look, height: 150, frozenAt: p),
                  ),
              ],
            ),
          ),
        ),
      ),
      'm6_01_eating_frames',
    );

    // 2) 보낸 사람이 보는 먹힌 편지
    final base = sampleReceived();
    final sent = Letter(
      id: 'sent-eaten',
      mode: LetterMode.direct,
      isSender: true,
      status: LetterStatus.eaten,
      sender: const Person(id: 'me', nickname: '나'),
      recipient: const Person(id: 'u-kong', nickname: '콩이네'),
      body: null,
      stationeryId: 'cream',
      stickers: const [],
      photo: null,
      handedAt: fixtureNow.subtract(const Duration(hours: 5)),
      goatName: '메롱이',
      goatLook: base.goatLook,
    );
    await captureScreen(
      tester,
      await app('/letters/sent-eaten', extra: sent),
      'm6_02_eaten_sender',
    );

    // 3) 신고 시트
    final got = sampleReceived(unread: false);
    await captureScreen(
      tester,
      await app('/letters/${got.id}', extra: got),
      'm6_03_report_sheet',
      beforeCapture: (t) async {
        await t.tap(find.byKey(const ValueKey('letter-more')));
        await t.pumpAndSettle();
        await t.tap(find.byKey(const ValueKey('menu-report')));
        await t.pumpAndSettle();
        await t.tap(find.byKey(const ValueKey('reason-ABUSE')));
        await t.tap(find.byKey(const ValueKey('also-block')));
      },
    );

    // 4) 두루마리에서 먹힌 글
    final p = FakeRollingApi.paper(RollingLevel.city, topic: '오늘 먹은 맛있는 것');
    await captureScreen(
      tester,
      await app(
        '/rolling/${p.id}',
        setup: (_, r) => r.views[RollingLevel.city] = FakeRollingApi.view(
          p,
          joined: true,
          block: JoinBlock.alreadyJoined,
          entries: [
            sampleEntry('a1', '콩이네', '떡볶이 최고!'),
            RollingEntry(
              id: 'b2',
              author: const Person(id: 'x', nickname: '광고봇'),
              body: null,
              stickers: const [],
              mine: false,
              eaten: true,
              createdAt: fixtureNow,
            ),
            sampleEntry('c3', '나', '김밥 먹었어요', mine: true),
          ],
        ),
      ),
      'm6_04_rolling_eaten',
    );

    // 5) 설정
    await captureScreen(
      tester,
      await app('/settings', setup: (s, _) => s.blocked.addAll({'u-kong': '콩이네', 'u-x': '심술염소'})),
      'm6_05_settings',
    );
  });
}
