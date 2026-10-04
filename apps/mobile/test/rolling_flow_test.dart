import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:meeil/app/app.dart';
import 'package:meeil/app/theme.dart';
import 'package:meeil/core/api_client.dart';
import 'package:meeil/core/token_store.dart';
import 'package:meeil/features/goats/hand_availability.dart';
import 'package:meeil/features/letters/letter_models.dart';
import 'package:meeil/features/rolling/rolling_album_screen.dart';
import 'package:meeil/features/rolling/rolling_models.dart';
import 'package:meeil/features/rolling/rolling_paper_screen.dart';
import 'package:meeil/features/rolling/rolling_tab.dart';
import 'package:meeil/features/rolling/rolling_texts.dart';
import 'package:meeil/features/rolling/rolling_widgets.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/fakes.dart';

typedef P = FakeRollingApi;

/// 서울 종로구에 있는 사용자의 이번 장 셋: 시는 참여 가능, 전국은 염소 대기, 도는 이미 참여
FakeRollingApi sampleRolling() {
  final api = FakeRollingApi(MemoryTokenStore());
  api.views[RollingLevel.city] = P.view(P.paper(RollingLevel.city), canJoin: true);
  api.views[RollingLevel.nation] = P.view(
    P.paper(
      RollingLevel.nation,
      scopeName: '전국',
      topic: '올가을 가장 좋았던 순간',
      start: DateTime.utc(2026, 9, 27, 15),
      end: DateTime.utc(2026, 10, 4, 15),
    ),
    block: JoinBlock.noGoatHere,
    next: DateTime.utc(2026, 10, 4, 6, 20), // 내일 오후 3:20 KST
    entries: [
      sampleEntry('n1', '두부염소', '다들 따뜻한 가을 보내요!'),
      sampleEntry('n2', '콩이네', '염소 너무 귀여워요', title: '단골 손님'),
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
    entries: [sampleEntry('p1', '나', '서울 최고', mine: true)],
  );
  return api;
}

Future<void> pumpRolling(
  WidgetTester tester, {
  required FakeRollingApi rolling,
  String initial = '/',
}) async {
  tester.view.physicalSize = const Size(1080, 2400);
  tester.view.devicePixelRatio = 2.625;
  addTearDown(tester.view.reset);
  tester.platformDispatcher.accessibilityFeaturesTestValue = const FakeAccessibilityFeatures(
    disableAnimations: true,
  );
  addTearDown(tester.platformDispatcher.clearAccessibilityFeaturesTestValue);
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
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  group('문구', () {
    final now = fixtureNow; // 10/3(토) 12:00 KST
    test('기간·마감·도착 시각은 KST', () {
      final city = P.paper(RollingLevel.city);
      expect(periodLabel(city), '10월 3일');
      expect(closesIn(city, now), '마감까지 12시간');
      final nation = P.paper(
        RollingLevel.nation,
        start: DateTime.utc(2026, 9, 27, 15),
        end: DateTime.utc(2026, 10, 4, 15),
      );
      expect(periodLabel(nation), '9월 28일 ~ 10월 4일');
      expect(closesIn(nation, now), '마감까지 2일');
      expect(dayClock(DateTime.utc(2026, 10, 3, 6), now), '오늘 오후 3:00');
      expect(dayClock(DateTime.utc(2026, 10, 3, 15, 5), now), '내일 오전 12:05');
      expect(dayClock(DateTime.utc(2026, 10, 7, 1), now), '10월 7일 오전 10:00');
    });

    test('제목과 참여 상태 한 줄', () {
      expect(P.paper(RollingLevel.city).title, '종로구 두루마리');
      expect(P.paper(RollingLevel.province, scopeName: '경기').title, '경기 두루마리');
      final wait = P.view(
        P.paper(RollingLevel.nation, scopeName: '전국'),
        block: JoinBlock.noGoatHere,
        next: DateTime.utc(2026, 10, 3, 6),
      );
      expect(joinStatusLine(wait, now), '전국 두루마리 염소가 오늘 오후 3:00에 와요');
      final never = P.view(P.paper(RollingLevel.province), block: JoinBlock.noGoatHere);
      expect(joinStatusLine(never, now), '이번 장엔 도 두루마리 염소가 우리 동네에 안 들러요');
      expect(
        joinStatusLine(P.view(P.paper(RollingLevel.city), canJoin: true), now),
        '지금 한마디 남길 수 있어요!',
      );
    });
  });

  testWidgets('롤링 탭: 세 레벨 카드와 상태', (tester) async {
    await pumpRolling(tester, rolling: sampleRolling());
    expect(find.text('전국 두루마리'), findsOneWidget);
    expect(find.text('서울 두루마리'), findsOneWidget);
    expect(find.text('종로구 두루마리'), findsOneWidget);
    expect(find.text('주제: 올가을 가장 좋았던 순간'), findsOneWidget);
    expect(find.text('지금 한마디 남길 수 있어요!'), findsOneWidget);
    expect(find.text('전국 두루마리 염소가 내일 오후 3:20에 와요'), findsOneWidget);
    expect(find.text('한마디 남겼어요'), findsOneWidget);
    expect(find.text('한마디 2개'), findsOneWidget);
  });

  testWidgets('위치를 모르면 도·시 카드 대신 위치 확인 안내', (tester) async {
    final api = sampleRolling();
    api.views.remove(RollingLevel.city);
    api.views.remove(RollingLevel.province);
    api.errors[RollingLevel.city] = 'REGION_UNKNOWN';
    api.errors[RollingLevel.province] = 'REGION_UNKNOWN';
    await pumpRolling(tester, rolling: api);
    expect(find.text('위치 확인하기'), findsNWidgets(2));
    expect(find.text('전국 두루마리'), findsOneWidget);
  });

  testWidgets('불러오기 실패 → 다시 시도', (tester) async {
    final api = sampleRolling()..fail = true;
    await pumpRolling(tester, rolling: api);
    expect(find.text('두루마리를 불러오지 못했어요.'), findsOneWidget);
    api.fail = false;
    await tester.tap(find.text('다시 시도'));
    await tester.pumpAndSettle();
    expect(find.text('종로구 두루마리'), findsOneWidget);
  });

  testWidgets('시 두루마리: 빈 장 → 한마디 + 스티커 남기기 → 내 글 표시', (tester) async {
    final api = sampleRolling();
    await pumpRolling(tester, rolling: api);
    await tester.tap(find.byKey(const ValueKey('rolling-card-CITY')));
    await tester.pumpAndSettle();
    expect(find.text('아직 비어 있어요.\n첫 한마디를 남겨 볼까요?'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('rolling-join')));
    await tester.pumpAndSettle();
    expect(find.text('종로구 두루마리에 한마디'), findsOneWidget);
    // 빈 글은 안 된다
    await tester.tap(find.byKey(const ValueKey('rolling-send')));
    await tester.pumpAndSettle();
    expect(find.text('한 마디라도 적어 주세요.'), findsOneWidget);
    expect(api.joins, isEmpty);

    await tester.enterText(find.byKey(const ValueKey('rolling-body')), '  종로 염소 안녕!  ');
    await tester.tap(find.bySemanticsLabel('하트 스티커 붙이기'));
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('rolling-send')));
    await tester.pumpAndSettle();

    expect(api.joins.single.$2, '종로 염소 안녕!');
    expect(api.joins.single.$3.single.id, 'heart');
    expect(find.byType(NoteCard), findsOneWidget);
    expect(find.text('내 글'), findsOneWidget);
    expect(find.text('한마디 남겼어요! 마감되면 앨범에 보관돼요.'), findsOneWidget);
    expect(find.byKey(const ValueKey('rolling-join')), findsNothing);
  });

  testWidgets('참여 실패(염소가 떠남)는 시트 안에 보인다', (tester) async {
    final api = sampleRolling()
      ..joinError = const ApiException('NO_GOAT_HERE', '두루마리 염소가 우리 동네에 오면 참여할 수 있어요.');
    await pumpRolling(tester, rolling: api, initial: '/rolling/paper-city');
    await tester.tap(find.byKey(const ValueKey('rolling-join')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const ValueKey('rolling-body')), '안녕');
    await tester.tap(find.byKey(const ValueKey('rolling-send')));
    await tester.pumpAndSettle();
    expect(find.text('두루마리 염소가 우리 동네에 오면 참여할 수 있어요.'), findsOneWidget);
    expect(find.text('종로구 두루마리에 한마디'), findsOneWidget);
  });

  testWidgets('염소가 없으면 참여 버튼 대신 다음 도착 시각', (tester) async {
    await pumpRolling(tester, rolling: sampleRolling(), initial: '/rolling/paper-nation');
    expect(find.text('다들 따뜻한 가을 보내요!'), findsOneWidget);
    expect(find.text('— 콩이네 · 단골 손님'), findsOneWidget);
    expect(find.byKey(const ValueKey('rolling-join')), findsNothing);
    expect(find.text('전국 두루마리 염소가 내일 오후 3:20에 와요'), findsOneWidget);
  });

  testWidgets('앨범: 비었을 때', (tester) async {
    final api = sampleRolling();
    await pumpRolling(tester, rolling: api, initial: '/rolling/album');
    expect(find.text('앨범이 아직 비었어요'), findsOneWidget);
  });

  testWidgets('앨범: 마감된 장 열어 보기(읽기 전용)', (tester) async {
    final api = sampleRolling();
    final old = P.paper(
      RollingLevel.city,
      id: 'old-city',
      start: DateTime.utc(2026, 9, 30, 15),
      end: DateTime.utc(2026, 10, 1, 15),
      entryCount: 3,
    );
    api.album_.add(old);
    api.closed['old-city'] = P.view(
      old,
      closed: true,
      joined: true,
      block: JoinBlock.closed,
      entries: [sampleEntry('o1', '나', '어제의 한마디', mine: true)],
    );
    await pumpRolling(tester, rolling: api, initial: '/rolling/album');
    expect(find.text('종로구 두루마리'), findsOneWidget);
    expect(find.text('10월 1일'), findsOneWidget);
    expect(find.text('한마디 3개'), findsOneWidget);
    await tester.tap(find.text('종로구 두루마리'));
    await tester.pumpAndSettle();
    expect(find.text('어제의 한마디'), findsOneWidget);
    expect(find.text('마감된 두루마리예요. 앨범에 영원히 보관돼요.'), findsOneWidget);
  });

  testWidgets('볼 수 없는 장(다른 지역)은 이유를 보여 준다', (tester) async {
    final api = sampleRolling();
    await pumpRolling(tester, rolling: api, initial: '/rolling/nope');
    expect(find.text('두루마리를 찾을 수 없어요.'), findsOneWidget);
  });

  test('쪽지 기울기·색은 id로 정해진다', () {
    final e = sampleEntry('x', 'a', 'b');
    expect(NoteCard(entry: e).entry.id, 'x');
    expect(const PlacedSticker('heart', 0.5, 0).toJson()['id'], 'heart');
  });
}
