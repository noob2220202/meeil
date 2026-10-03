import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:meeil/app/app.dart';
import 'package:meeil/app/theme.dart';
import 'package:meeil/core/api_client.dart';
import 'package:meeil/core/push.dart';
import 'package:meeil/core/token_store.dart';
import 'package:meeil/features/goats/hand_availability.dart';
import 'package:meeil/features/goats/schedule.dart';
import 'package:meeil/features/letters/compose_screen.dart';
import 'package:meeil/features/letters/letter_models.dart';
import 'package:meeil/features/letters/letter_screen.dart';
import 'package:meeil/features/letters/letters_api.dart';
import 'package:meeil/features/letters/mailbox_tab.dart';
import 'package:meeil/features/location/my_region.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/fakes.dart';

/// 지금(픽스처 시각) 배달 염소가 머무는 시 / 없는 시
(String withGoat, String withoutGoat, GoatInfo goat) regions() {
  final schedule = loadScheduleFixture();
  final stayingTrack = schedule.tracks.values.firstWhere(
    (tr) => tr.goat.kind == GoatKind.delivery && tr.at(fixtureNow) is GoatStaying,
  );
  final here = (stayingTrack.at(fixtureNow) as GoatStaying).stop.regionCode;
  final empty = testRegionData.regions
      .map((r) => r.code)
      .firstWhere((c) => schedule.deliveryGoatsIn(c, fixtureNow).isEmpty);
  return (here, empty, stayingTrack.goat);
}

Future<void> pumpApp(
  WidgetTester tester, {
  required String region,
  required FakeLettersApi letters,
  String initial = '/compose',
}) async {
  tester.view.physicalSize = const Size(1080, 2400);
  tester.view.devicePixelRatio = 2.625;
  addTearDown(tester.view.reset);
  tester.platformDispatcher.accessibilityFeaturesTestValue = const FakeAccessibilityFeatures(
    disableAnimations: true,
  );
  addTearDown(tester.platformDispatcher.clearAccessibilityFeaturesTestValue);

  final r = testRegionData.byCode[region]!;
  final store = MemoryTokenStore()
    ..tokens = const Tokens(accessToken: 'access:u1', refreshToken: 'r');
  final overrides = await appOverrides(
    backend: FakeBackend(),
    store: store,
    letters: letters,
    location: FakeLocationSource(fix: LocationFix(r.centerLon, r.centerLat)),
  );
  final router = GoRouter(
    initialLocation: initial,
    routes: [
      GoRoute(
        path: '/',
        builder: (_, s) => Scaffold(
          body: MailboxTab(
            initialBox: s.uri.queryParameters['box'] == 'sent' ? MailBox.sent : MailBox.inbox,
          ),
        ),
      ),
      GoRoute(path: '/compose', builder: (_, _) => const ComposeScreen()),
      GoRoute(
        path: '/letters/:id',
        builder: (_, s) => LetterScreen(
          id: s.pathParameters['id']!,
          initial: s.extra is Letter ? s.extra! as Letter : null,
        ),
      ),
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
  // 위치 판정(내 시) 반영
  final container = ProviderScope.containerOf(tester.element(find.byType(MaterialApp)));
  await container.read(myRegionProvider.notifier).refresh();
  await tester.pumpAndSettle();
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('염소가 와 있으면 지정 편지를 맡기고, 보낸 편지함으로 간다', (tester) async {
    final (here, _, goat) = regions();
    final letters = FakeLettersApi(MemoryTokenStore());
    await pumpApp(tester, region: here, letters: letters);

    // 받는 사람 고르기 전에는 버튼이 안내 문구
    expect(find.text('받는 사람을 골라 주세요'), findsOneWidget);

    await tester.tap(find.text('닉네임으로 받는 사람 찾기'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), '두부');
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pumpAndSettle();
    await tester.tap(find.text('두부염소'));
    await tester.pumpAndSettle();
    expect(find.text('두부염소님에게'), findsOneWidget);

    await tester.enterText(find.byType(TextField), '  안녕! 염소 편으로 보내는 편지야.  ');
    await tester.pump();
    expect(find.text('${goat.name}에게 맡기기 · 1P'), findsOneWidget);

    // 스티커 하나(아래로 스크롤)
    final semantics = tester.ensureSemantics();
    await tester.drag(find.byType(ListView).first, const Offset(0, -700));
    await tester.pumpAndSettle();
    await tester.tap(find.bySemanticsLabel('하트 스티커 붙이기'));
    await tester.pump();
    semantics.dispose();

    await tester.tap(find.text('${goat.name}에게 맡기기 · 1P'));
    await tester.pumpAndSettle();

    expect(letters.handed, hasLength(1));
    final req = letters.handed.single;
    expect(req.mode, LetterMode.direct);
    expect(req.recipientId, 'u-dubu');
    expect(req.body, '안녕! 염소 편으로 보내는 편지야.');
    expect(req.stickers.map((s) => s.id), ['heart']);
    expect(req.clientRequestId, hasLength(32));

    // 맡기기 연출
    expect(find.textContaining('출발했어요!'), findsOneWidget);
    await tester.tapAt(const Offset(200, 200));
    await tester.pumpAndSettle();

    // 보낸 편지함: 이동 중
    expect(find.text('두부염소님에게'), findsOneWidget);
    expect(find.textContaining('메롱이가 가는 중'), findsOneWidget);
  });

  testWidgets('염소가 없으면 맡기기 버튼이 꺼지고 다음 염소를 알려 준다', (tester) async {
    final (_, empty, _) = regions();
    await pumpApp(tester, region: empty, letters: FakeLettersApi(MemoryTokenStore()));
    await tester.tap(find.text('랜덤으로 보내기'));
    await tester.pump();
    await tester.enterText(find.byType(TextField), '누군가에게');
    await tester.pump();
    expect(find.text('염소를 기다리는 중'), findsOneWidget);
    expect(find.textContaining('다음 염소 '), findsOneWidget);
    expect(find.textContaining('쓰던 편지는 저장돼요'), findsOneWidget);
  });

  testWidgets('쓰던 편지는 화면을 나갔다 와도 남아 있다', (tester) async {
    final (_, empty, _) = regions();
    final letters = FakeLettersApi(MemoryTokenStore());
    await pumpApp(tester, region: empty, letters: letters);
    await tester.enterText(find.byType(TextField), '임시저장 확인');
    await tester.pump(const Duration(milliseconds: 400));

    // 새 앱 실행(같은 SharedPreferences)
    await tester.pumpWidget(Container());
    await pumpApp(tester, region: empty, letters: letters);
    expect(find.text('임시저장 확인'), findsOneWidget);
  });

  testWidgets('서버 거절 문구를 그대로 보여 주고 임시저장은 지우지 않는다', (tester) async {
    final (here, _, goat) = regions();
    final letters = FakeLettersApi(MemoryTokenStore())
      ..handError = const ApiException('INSUFFICIENT_POINTS', '포인트가 부족해요.', statusCode: 409);
    await pumpApp(tester, region: here, letters: letters);
    await tester.tap(find.text('랜덤으로 보내기'));
    await tester.pump();
    await tester.enterText(find.byType(TextField), '포인트 없을 때');
    await tester.pump();
    await tester.tap(find.text('${goat.name}에게 맡기기 · 1P'));
    await tester.pumpAndSettle();
    expect(find.textContaining('포인트가 부족해요'), findsOneWidget);
    expect(find.text('포인트 없을 때'), findsOneWidget);
  });

  testWidgets('받은 편지: 새 편지 → 열면(연출 생략) 읽음 → 답장 버튼', (tester) async {
    final (here, _, _) = regions();
    final letters = FakeLettersApi(MemoryTokenStore())..inbox.add(sampleReceived());
    await pumpApp(tester, region: here, letters: letters, initial: '/');
    expect(find.text('두부염소님의 편지'), findsOneWidget);
    expect(find.text('새 편지'), findsOneWidget);

    await tester.tap(find.text('두부염소님의 편지'));
    await tester.pumpAndSettle();
    expect(find.textContaining('메롱이가 왔어!'), findsOneWidget);
    expect(find.textContaining('— 두부염소'), findsOneWidget);
    expect(find.text('답장 쓰기'), findsOneWidget);
    expect(letters.inbox.single.status, LetterStatus.read);
  });

  testWidgets('빈 편지함 안내', (tester) async {
    final (here, _, _) = regions();
    await pumpApp(tester, region: here, letters: FakeLettersApi(MemoryTokenStore()), initial: '/');
    expect(find.text('아직 받은 편지가 없어요'), findsOneWidget);
    await tester.tap(find.text('휴지통'));
    await tester.pumpAndSettle();
    expect(find.text('휴지통이 비어 있어요'), findsOneWidget);
  });

  test('알림을 누르면 열 화면', () {
    expect(routeForPush({'type': 'letter', 'letterId': 'abc'}), '/letters/abc');
    expect(routeForPush({'type': 'goat'}), '/');
    expect(routeForPush({'type': 'unknown'}), isNull);
  });
}
