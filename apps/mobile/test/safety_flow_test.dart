import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:meeil/app/app.dart';
import 'package:meeil/app/theme.dart';
import 'package:meeil/core/push.dart';
import 'package:meeil/core/token_store.dart';
import 'package:meeil/features/goats/hand_availability.dart';
import 'package:meeil/features/letters/letter_models.dart';
import 'package:meeil/features/letters/letter_screen.dart';
import 'package:meeil/features/rolling/rolling_models.dart';
import 'package:meeil/features/rolling/rolling_paper_screen.dart';
import 'package:meeil/features/safety/goat_eating.dart';
import 'package:meeil/features/safety/notices_screen.dart';
import 'package:meeil/features/safety/safety_api.dart';
import 'package:meeil/features/safety/settings_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/fakes.dart';

class World {
  World() {
    tokens = backend.signedUp('나');
    store.tokens = tokens;
    safety = FakeSafetyApi(store, backend: backend);
  }
  final backend = FakeBackend();
  final store = MemoryTokenStore();
  late final Tokens tokens;
  late final FakeSafetyApi safety;
  final letters = FakeLettersApi(MemoryTokenStore());
  final rolling = FakeRollingApi(MemoryTokenStore());
}

Future<GoRouter> pump(WidgetTester tester, World w) async {
  tester.view.physicalSize = const Size(1080, 2400);
  tester.view.devicePixelRatio = 2.625;
  addTearDown(tester.view.reset);
  tester.platformDispatcher.accessibilityFeaturesTestValue = const FakeAccessibilityFeatures(
    disableAnimations: true,
  );
  addTearDown(tester.platformDispatcher.clearAccessibilityFeaturesTestValue);
  final List<Override> overrides = await appOverrides(
    backend: w.backend,
    store: w.store,
    letters: w.letters,
    rolling: w.rolling,
    safety: w.safety,
  );
  final router = GoRouter(
    initialLocation: '/',
    routes: [
      GoRoute(
        path: '/',
        builder: (_, _) => const Scaffold(body: Center(child: Text('홈'))),
      ),
      GoRoute(
        path: '/letters/:id',
        builder: (_, s) => LetterScreen(
          id: s.pathParameters['id']!,
          initial: s.extra is Letter ? s.extra! as Letter : null,
        ),
      ),
      GoRoute(
        path: '/rolling/:id',
        builder: (_, s) => RollingPaperScreen(id: s.pathParameters['id']!),
      ),
      GoRoute(path: '/settings', builder: (_, _) => const SettingsScreen()),
      GoRoute(path: '/notices', builder: (_, _) => const NoticesScreen()),
    ],
  );
  await tester.pumpWidget(
    ProviderScope(
      overrides: [...overrides, clockTickProvider.overrideWith(() => FixedClock(fixtureNow))],
      child: MaterialApp.router(
        theme: buildTheme(),
        locale: appLocale,
        supportedLocales: const [appLocale],
        localizationsDelegates: appLocalizationsDelegates,
        routerConfig: router,
      ),
    ),
  );
  await tester.pumpAndSettle();
  return router;
}

Letter eatenSent({bool delivered = false}) {
  final base = sampleReceived(eaten: true);
  return Letter(
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
    deliveredAt: delivered ? fixtureNow.subtract(const Duration(hours: 1)) : null,
    goatId: base.goatId,
    goatName: '메롱이',
    goatLook: base.goatLook,
  );
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('받은 편지 신고 + 차단 → 신고 기록, 편지 화면 닫힘', (tester) async {
    final w = World();
    final l = sampleReceived(unread: false);
    w.letters.inbox.add(l);
    final router = await pump(tester, w);
    router.push('/letters/${l.id}', extra: l);
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('letter-more')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('menu-report')));
    await tester.pumpAndSettle();
    expect(find.text('편지 신고하기'), findsOneWidget);

    // 이유를 안 고르면 안내
    await tester.tap(find.byKey(const ValueKey('send-report')));
    await tester.pumpAndSettle();
    expect(find.text('신고 이유를 골라 주세요.'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('reason-ABUSE')));
    await tester.enterText(find.byKey(const ValueKey('report-detail')), '  나쁜 말을 했어요 ');
    await tester.tap(find.byKey(const ValueKey('also-block')));
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('send-report')));
    await tester.pumpAndSettle();

    expect(w.safety.reports.single, (ReportTarget.letter, l.id, 'ABUSE', '나쁜 말을 했어요'));
    expect(w.safety.blocked.keys, ['u-dubu']);
    expect(find.text('신고하고 차단했어요. 운영자가 확인할게요.'), findsOneWidget);
    expect(find.text('홈'), findsOneWidget); // 차단하면 편지 화면을 닫는다
  });

  testWidgets('차단만: 확인 창을 거친다', (tester) async {
    final w = World();
    final l = sampleReceived(unread: false);
    w.letters.inbox.add(l);
    final router = await pump(tester, w);
    router.push('/letters/${l.id}', extra: l);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('letter-more')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('menu-block')));
    await tester.pumpAndSettle();
    expect(find.text('두부염소님을 차단할까요?'), findsOneWidget);
    await tester.tap(find.text('취소'));
    await tester.pumpAndSettle();
    expect(w.safety.blocked, isEmpty);
  });

  testWidgets('먹힌 편지: 보낸 사람(배달 전)·받은 사람 문구, 신고 메뉴 없음', (tester) async {
    final w = World();
    final sent = eatenSent();
    final got = sampleReceived(id: 'got-eaten', eaten: true);
    w.letters.sent.add(sent);
    w.letters.inbox.add(got);
    final router = await pump(tester, w);
    router.push('/letters/${sent.id}', extra: sent);
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('eaten-letter')), findsOneWidget);
    expect(find.text('메롱이가 편지를 먹어버렸어요'), findsOneWidget);
    expect(find.textContaining('콩이네님에게 가는 길에 꿀꺽'), findsOneWidget);
    expect(find.byKey(const ValueKey('letter-more')), findsNothing);

    router.go('/');
    await tester.pumpAndSettle();
    router.push('/letters/${got.id}', extra: got);
    await tester.pumpAndSettle();
    expect(find.text('염소가 먹어버린 편지'), findsOneWidget);
    expect(find.byType(GoatEatingScene), findsOneWidget);
    expect(find.byKey(const ValueKey('letter-more')), findsNothing);
  });

  testWidgets('두루마리: 남의 쪽지를 길게 눌러 신고, 먹힌 글은 염소 연출', (tester) async {
    final w = World();
    final p = FakeRollingApi.paper(RollingLevel.city);
    w.rolling.views[RollingLevel.city] = FakeRollingApi.view(
      p,
      entries: [
        sampleEntry('e1', '콩이네', '안녕 종로!'),
        sampleEntry('e2', '나', '제 한마디', mine: true),
        RollingEntry(
          id: 'e3',
          author: const Person(id: 'u-x', nickname: '광고봇'),
          body: null,
          stickers: const [],
          mine: false,
          eaten: true,
          createdAt: fixtureNow,
        ),
      ],
    );
    final router = await pump(tester, w);
    router.push('/rolling/${p.id}');
    await tester.pumpAndSettle();
    expect(find.text('염소가 먹어 버린 한마디예요'), findsOneWidget);

    await tester.longPress(find.text('안녕 종로!'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('menu-report')));
    await tester.pumpAndSettle();
    expect(find.text('두루마리 글 신고하기'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('reason-SPAM')));
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('send-report')));
    await tester.pumpAndSettle();
    expect(w.safety.reports.single, (ReportTarget.rollingEntry, 'e1', 'SPAM', null));

    // 내 글은 길게 눌러도 메뉴가 없다
    await tester.longPress(find.text('제 한마디'));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('menu-report')), findsNothing);
  });

  testWidgets('설정: 랜덤 편지 끄기, 차단 풀기, 공지', (tester) async {
    final w = World();
    w.safety.blocked['u-kong'] = '콩이네';
    w.safety.notices_.add(
      Notice(id: 'n1', title: '염소 우체국 개국!', body: '반가워요.', pinned: true, publishedAt: fixtureNow),
    );
    final router = await pump(tester, w);
    // 세션이 내 정보를 갖도록 잠깐 기다린다
    router.push('/settings');
    await tester.pumpAndSettle();
    final random = find.byKey(const ValueKey('switch-random'));
    expect(tester.widget<SwitchListTile>(random).value, isTrue);
    await tester.tap(random);
    await tester.pumpAndSettle();
    expect(w.safety.settings['randomReceive'], isFalse);
    expect(tester.widget<SwitchListTile>(random).value, isFalse);

    expect(find.text('콩이네'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('unblock-u-kong')));
    await tester.pumpAndSettle();
    expect(find.text('차단한 사람이 없어요.'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('open-notices')));
    await tester.pumpAndSettle();
    expect(find.text('염소 우체국 개국!'), findsOneWidget);
  });

  test('푸시 알림 → 열 화면', () {
    expect(routeForPush({'type': 'letter-eaten', 'letterId': 'x'}), '/letters/x');
    expect(routeForPush({'type': 'rolling-eaten', 'paperId': 'p'}), '/rolling/p');
    expect(routeForPush({'type': 'notice', 'noticeId': 'n'}), '/notices');
    expect(routeForPush({'type': 'sanction'}), isNull);
  });
}
