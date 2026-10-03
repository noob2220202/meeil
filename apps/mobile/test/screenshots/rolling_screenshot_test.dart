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
import 'package:meeil/features/rolling/rolling_album_screen.dart';
import 'package:meeil/features/rolling/rolling_models.dart';
import 'package:meeil/features/rolling/rolling_paper_screen.dart';
import 'package:meeil/features/rolling/rolling_tab.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../support/fakes.dart';
import 'screenshot_helper.dart';

typedef P = FakeRollingApi;

FakeRollingApi rich() {
  final api = FakeRollingApi(MemoryTokenStore());
  api.views[RollingLevel.nation] = P.view(
    P.paper(
      RollingLevel.nation,
      scopeName: '전국',
      topic: '올가을 가장 좋았던 순간',
      start: DateTime.utc(2026, 9, 27, 15),
      end: DateTime.utc(2026, 10, 4, 15),
    ),
    block: JoinBlock.noGoatHere,
    next: DateTime.utc(2026, 10, 4, 6, 20),
    entries: [
      sampleEntry(
        'n-a1',
        '두부염소',
        '다들 따뜻한 가을 보내요! 단풍 보러 가요 🍁',
        stickers: const [PlacedSticker('leaf', 0.9, 0)],
      ),
      sampleEntry('n-b2', '콩이네', '강릉 바다에서 본 노을이 최고였어요', title: '단골 손님'),
      sampleEntry(
        'n-c3',
        '귤껍질',
        '제주에서 인사 보내요~ 귤 맛있게 익는 중',
        stickers: const [PlacedSticker('sun', 0.05, 0)],
      ),
      sampleEntry('n-d4', '메에메에', '염소들 오늘도 수고했어'),
      sampleEntry(
        'n-e5',
        '산책왕',
        '주말에 할머니 댁에 다녀왔어요. 감 따기 재밌었다!',
        stickers: const [PlacedSticker('goat-smile', 0.85, 0)],
      ),
    ],
  );
  api.views[RollingLevel.province] = P.view(
    P.paper(
      RollingLevel.province,
      scopeName: '서울',
      start: DateTime.utc(2026, 10, 1, 15),
      end: DateTime.utc(2026, 10, 4, 15),
    ),
    joined: true,
    block: JoinBlock.alreadyJoined,
    entries: [
      sampleEntry('p1', '나', '서울 친구들 안녕', mine: true),
      sampleEntry('p2', '한강러', '한강 자전거 타기 좋은 날씨'),
      sampleEntry('p3', '북촌', '골목길 산책 추천해요'),
    ],
  );
  api.views[RollingLevel.city] = P.view(
    P.paper(RollingLevel.city, topic: '오늘 먹은 맛있는 것'),
    canJoin: true,
  );
  return api;
}

Future<Widget> app(FakeRollingApi rolling, String initial) async {
  final store = MemoryTokenStore()
    ..tokens = const Tokens(accessToken: 'access:u1', refreshToken: 'r');
  final overrides = await appOverrides(backend: FakeBackend(), store: store, rolling: rolling);
  final router = GoRouter(
    initialLocation: initial,
    routes: [
      GoRoute(
        path: '/',
        builder: (_, _) => const Scaffold(body: RollingTab()),
      ),
      GoRoute(path: '/rolling/album', builder: (_, _) => const RollingAlbumScreen()),
      GoRoute(
        path: '/rolling/:id',
        builder: (_, s) => RollingPaperScreen(id: s.pathParameters['id']!),
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

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('M4 롤링페이퍼 화면들', (tester) async {
    await tester.runAsync(loadAppFonts);

    await captureScreen(tester, await app(rich(), '/'), 'm4_01_rolling_tab');
    await captureScreen(tester, await app(rich(), '/rolling/paper-nation'), 'm4_02_nation_paper');
    await captureScreen(tester, await app(rich(), '/rolling/paper-city'), 'm4_03_city_empty');
    await captureScreen(
      tester,
      await app(rich(), '/rolling/paper-city'),
      'm4_04_join_sheet',
      beforeCapture: (t) async {
        await t.tap(find.byKey(const ValueKey('rolling-join')));
        await t.pumpAndSettle();
        await t.enterText(find.byKey(const ValueKey('rolling-body')), '떡볶이 먹었어요! 종로 최고 🐐');
        await t.tap(find.bySemanticsLabel('하트 스티커 붙이기'));
        await t.tap(find.bySemanticsLabel('별 스티커 붙이기'));
        await t.pump();
      },
    );

    final withAlbum = rich();
    for (final (i, level) in [
      RollingLevel.city,
      RollingLevel.province,
      RollingLevel.nation,
    ].indexed) {
      withAlbum.album_.add(
        P.paper(
          level,
          id: 'old-$i',
          scopeName: level == RollingLevel.nation
              ? '전국'
              : level == RollingLevel.province
              ? '서울'
              : '서울 종로구',
          topic: i == 2 ? '여름 방학 이야기' : null,
          start: DateTime.utc(2026, 9, 20 - i * 7, 15),
          end: DateTime.utc(2026, 9, 21 - i * 7 + (i == 0 ? 0 : 3 + i), 15),
          entryCount: 4 + i * 9,
        ),
      );
    }
    await captureScreen(tester, await app(withAlbum, '/rolling/album'), 'm4_05_album');
    await captureScreen(tester, await app(rich(), '/rolling/album'), 'm4_06_album_empty');
  });
}
