@Tags(['screenshot'])
library;

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:meeil/app/app.dart';
import 'package:meeil/app/theme.dart';
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

import '../support/fakes.dart';
import 'screenshot_helper.dart';

(String, String) regionsNow() {
  final s = loadScheduleFixture();
  final here = s.tracks.values
      .map((tr) => tr.at(fixtureNow))
      .whereType<GoatStaying>()
      .firstWhere((m) => s.deliveryGoatsIn(m.stop.regionCode, fixtureNow).isNotEmpty)
      .stop
      .regionCode;
  final empty = testRegionData.regions
      .map((r) => r.code)
      .firstWhere((c) => s.deliveryGoatsIn(c, fixtureNow).isEmpty);
  return (here, empty);
}

Future<Widget> app({
  required String region,
  required FakeLettersApi letters,
  required String initial,
}) async {
  final r = testRegionData.byCode[region]!;
  final store = MemoryTokenStore()
    ..tokens = const Tokens(accessToken: 'access:u1', refreshToken: 'r');
  final backend = FakeBackend();
  final overrides = await appOverrides(
    backend: backend,
    store: store,
    rewards: FakeRewardsApi(backend, store)..owned.add('lined'),
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

Future<void> locate(WidgetTester t) async {
  final c = ProviderScope.containerOf(t.element(find.byType(MaterialApp)));
  await c.read(myRegionProvider.notifier).refresh();
}

void draft(Map<String, Object?> j) => SharedPreferences.setMockInitialValues({
  'compose.draft.v1': jsonEncode({'clientRequestId': 'c' * 32, ...j}),
});

void main() {
  testWidgets('M3 편지 화면들', (tester) async {
    await tester.runAsync(loadAppFonts);
    final (here, empty) = regionsNow();

    // 1) 쓰기: 염소가 와 있음
    draft({
      'mode': 'direct',
      'recipient': {'id': 'u-dubu', 'nickname': '두부염소'},
      'body': '두부야 안녕!\n오늘 우리 동네에 메롱이가 왔어. 생각나서 편지 맡긴다.\n다음 주에 떡볶이 먹자 🐐',
      'stationeryId': 'cream',
      'stickers': [
        {'id': 'heart', 'x': 0.92, 'y': 0.03},
        {'id': 'goat-love', 'x': 0.06, 'y': 0.95},
      ],
    });
    final letters = FakeLettersApi(MemoryTokenStore());
    await captureScreen(
      tester,
      await app(region: here, letters: letters, initial: '/compose'),
      'm3_01_compose_ready',
      beforeCapture: locate,
    );

    // 2) 쓰기: 줄노트, 염소 기다리는 중(랜덤)
    draft({
      'mode': 'random',
      'randomScope': 'province',
      'body': '안녕, 처음 보는 친구!\n염소가 골라 준 사람이 너래.',
      'stationeryId': 'lined',
      'stickers': [
        {'id': 'clover', 'x': 0.9, 'y': 0.05},
      ],
    });
    await captureScreen(
      tester,
      await app(region: empty, letters: FakeLettersApi(MemoryTokenStore()), initial: '/compose'),
      'm3_02_compose_waiting',
      beforeCapture: (t) async {
        await locate(t);
        await t.pump();
        await t.drag(find.byType(ListView).first, const Offset(0, -420));
      },
    );

    // 3) 맡기기 연출
    draft({
      'mode': 'direct',
      'recipient': {'id': 'u-dubu', 'nickname': '두부염소'},
      'body': '맡겨요!',
    });
    final l3 = FakeLettersApi(MemoryTokenStore());
    await captureScreen(
      tester,
      await app(region: here, letters: l3, initial: '/compose'),
      'm3_03_handoff',
      beforeCapture: (t) async {
        await locate(t);
        await t.pumpAndSettle();
        await t.tap(find.textContaining('에게 맡기기 · 1P'));
      },
    );

    // 4) 받은 편지함
    SharedPreferences.setMockInitialValues({});
    final box = FakeLettersApi(MemoryTokenStore())
      ..inbox.addAll([
        sampleReceived(),
        sampleReceived(id: 'in-2', unread: false, stationeryId: 'lined', body: '어제 보내 준 편지 잘 받았어!'),
        sampleReceived(id: 'in-3', unread: false, mode: LetterMode.random, body: '랜덤으로 만난 친구에게'),
      ]);
    await captureScreen(tester, await app(region: here, letters: box, initial: '/'), 'm3_04_inbox');

    // 5) 보낸 편지함
    final sentBox = FakeLettersApi(MemoryTokenStore());
    await sentBox.hand(
      const HandRequest(
        mode: LetterMode.direct,
        body: '잘 지내?',
        stationeryId: 'cream',
        stickers: [],
        clientRequestId: 'x',
        recipientId: 'u-kong',
      ),
    );
    await sentBox.hand(
      const HandRequest(
        mode: LetterMode.random,
        body: '누군가에게',
        stationeryId: 'lined',
        stickers: [],
        clientRequestId: 'y',
      ),
    );
    await captureScreen(
      tester,
      await app(region: here, letters: sentBox, initial: '/?box=sent'),
      'm3_05_sent',
    );

    // 6) 편지 읽기(하늘 구름)
    final read = FakeLettersApi(MemoryTokenStore())
      ..inbox.add(
        sampleReceived(
          unread: false,
          stationeryId: 'sky-cloud',
          body: '구름 편지지 예쁘지?\n출석 7일 채우고 받았어.\n너도 얼른 모아서 써 봐!',
        ),
      );
    await captureScreen(
      tester,
      await app(region: here, letters: read, initial: '/letters/in-1'),
      'm3_06_letter',
    );

    // 7) 보낸 편지 여정
    await captureScreen(
      tester,
      await app(region: here, letters: sentBox, initial: '/letters/sent-1'),
      'm3_07_journey',
    );

    // 8) 도착 연출(진행 70%에서 멈춤)
    await captureScreen(
      tester,
      ProviderScope(
        overrides: await appOverrides(backend: FakeBackend(), store: MemoryTokenStore()),
        child: MaterialApp(
          theme: buildTheme(),
          debugShowCheckedModeBanner: false,
          home: ArrivalScene(letter: sampleReceived(), onDone: () {}, frozenAt: 0.72),
        ),
      ),
      'm3_08_arrival',
    );

    // 9) 빈 받은 편지함
    await captureScreen(
      tester,
      await app(region: here, letters: FakeLettersApi(MemoryTokenStore()), initial: '/'),
      'm3_09_inbox_empty',
    );
  });
}
