import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:meeil/app/app.dart';
import 'package:meeil/core/token_store.dart';
import 'package:meeil/features/rewards/ad_gateway.dart';
import 'package:meeil/features/rewards/rewards_models.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/fakes.dart';

/// 로그인된 앱을 띄우고 내 정보 탭으로 간다
Future<(FakeBackend, Tokens)> openProfile(
  WidgetTester tester, {
  required FakeRewardsApi Function(FakeBackend, MemoryTokenStore) rewards,
  FakeAdGateway? ads,
  int points = 5,
  bool toProfile = true,
}) async {
  tester.view.physicalSize = const Size(1080, 2400);
  tester.view.devicePixelRatio = 2.625;
  addTearDown(tester.view.reset);
  tester.platformDispatcher.accessibilityFeaturesTestValue = const FakeAccessibilityFeatures(
    disableAnimations: true,
  );
  addTearDown(tester.platformDispatcher.clearAccessibilityFeaturesTestValue);
  SharedPreferences.setMockInitialValues({
    'flags.introSeen': true,
    'flags.permissionsIntroDone': true,
  });
  final backend = FakeBackend();
  final tokens = backend.signedUp('풀뜯기', points: points);
  final store = MemoryTokenStore()..tokens = tokens;
  final List<Override> overrides = await appOverrides(
    backend: backend,
    store: store,
    rewards: rewards(backend, store),
    ads: ads,
  );
  await tester.pumpWidget(ProviderScope(overrides: overrides, child: const MeeilApp()));
  await tester.pumpAndSettle();
  if (toProfile) {
    await tester.tap(find.text('내 정보'));
    await tester.pumpAndSettle();
  }
  return (backend, tokens);
}

void main() {
  testWidgets('출석: 내 정보 배지 → 출석하면 +3P 축하, 하루 한 번만', (tester) async {
    late FakeRewardsApi api;
    final (backend, tokens) = await openProfile(
      tester,
      rewards: (b, s) => api = FakeRewardsApi(b, s),
    );
    expect(find.byKey(const ValueKey('points-balance')), findsOneWidget);
    expect(find.text('5P'), findsOneWidget);
    expect(find.text('출석 체크'), findsOneWidget);
    expect(find.text('+3P 받기'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('tile-attendance')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('attendance-dialog')), findsOneWidget);
    expect(find.text('+3P'), findsOneWidget);
    expect(find.text('출석 완료!'), findsOneWidget);
    await tester.tap(find.text('좋아요!'));
    await tester.pumpAndSettle();

    // 출석 화면: 달력에 오늘 도장, 버튼 대신 완료 안내
    expect(find.text('출석 체크'), findsWidgets);
    expect(find.text('1일 연속 출석 중'), findsOneWidget);
    expect(find.bySemanticsLabel('3일, 출석, 오늘'), findsOneWidget);
    expect(find.text('오늘 출석을 마쳤어요. 내일 또 만나요!'), findsOneWidget);
    expect(find.byKey(const ValueKey('check-in')), findsNothing);
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.text('8P'), findsOneWidget);
    expect(find.text('1일 연속 출석 중'), findsOneWidget);
    expect(backend.pointsOf(tokens), 8);
    expect(api.days, {'2026-10-03'});
  });

  testWidgets('7일째 출석은 연속 보너스까지', (tester) async {
    await openProfile(
      tester,
      rewards: (b, s) => FakeRewardsApi(b, s)
        ..streak = 6
        ..days.addAll([
          '2026-09-27',
          '2026-09-28',
          '2026-09-29',
          '2026-09-30',
          '2026-10-01',
          '2026-10-02',
        ]),
    );
    await tester.tap(find.byKey(const ValueKey('tile-attendance')));
    await tester.pumpAndSettle();
    expect(find.text('+8P'), findsOneWidget);
    expect(find.text('7일 연속 출석!'), findsOneWidget);
  });

  testWidgets('광고: 끝까지 보면 +2P, 닫으면 안내, 5번이면 끝', (tester) async {
    final ads = FakeAdGateway();
    late FakeRewardsApi api;
    await openProfile(tester, rewards: (b, s) => api = FakeRewardsApi(b, s), ads: ads);
    expect(find.text('오늘 5번 더 볼 수 있어요'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('tile-ad')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('ad-dialog')), findsOneWidget);
    expect(find.text('+2P'), findsOneWidget);
    await tester.tap(find.text('좋아요!'));
    await tester.pumpAndSettle();
    expect(find.text('7P'), findsOneWidget);
    expect(find.text('오늘 4번 더 볼 수 있어요'), findsOneWidget);

    ads.result = AdShowResult.dismissed;
    await tester.tap(find.byKey(const ValueKey('tile-ad')));
    await tester.pumpAndSettle();
    expect(find.text('광고를 끝까지 보면 포인트를 받아요.'), findsOneWidget);
    expect(api.adToday, 1);

    api.adToday = 5;
    await tester.drag(find.byType(ListView).first, const Offset(0, 300));
    await tester.pumpAndSettle();
    expect(find.text('오늘은 다 봤어요. 내일 또 만나요!'), findsOneWidget);
    final shownBefore = ads.shown;
    await tester.tap(find.byKey(const ValueKey('tile-ad')));
    await tester.pumpAndSettle();
    expect(ads.shown, shownBefore);
  });

  testWidgets('광고를 못 불러오면 안내만', (tester) async {
    await openProfile(
      tester,
      rewards: FakeRewardsApi.new,
      ads: FakeAdGateway(result: AdShowResult.failed),
    );
    await tester.tap(find.byKey(const ValueKey('tile-ad')));
    await tester.pumpAndSettle();
    expect(find.text('지금은 볼 수 있는 광고가 없어요. 조금 뒤에 다시 해 주세요.'), findsOneWidget);
  });

  testWidgets('새 업적은 축하 창 → 닫으면 본 것으로 표시', (tester) async {
    late FakeRewardsApi api;
    await openProfile(
      tester,
      toProfile: false,
      rewards: (b, s) => api = FakeRewardsApi(b, s)
        ..pending.add(
          const Achievement(
            id: 'attend-7',
            name: '출석 7일',
            description: '7일 출석했어요',
            rewardPoints: 3,
            stationeryId: 'lined',
            stationeryName: '줄노트',
            achieved: true,
          ),
        ),
    );
    expect(find.byKey(const ValueKey('achievement-dialog')), findsOneWidget);
    expect(find.text('업적 달성!'), findsOneWidget);
    expect(find.text('출석 7일'), findsWidgets);
    expect(find.text('편지지 「줄노트」'), findsOneWidget);
    await tester.tap(find.text('좋아요!'));
    await tester.pumpAndSettle();
    expect(api.seen, ['attend-7']);
    expect(find.byKey(const ValueKey('achievement-dialog')), findsNothing);
  });

  testWidgets('업적 화면: 진행도, 칭호 달기 → 닉네임 옆에 표시', (tester) async {
    await openProfile(tester, rewards: FakeRewardsApi.new);
    expect(find.text('칭호를 골라 보세요'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('menu-achievements')));
    await tester.pumpAndSettle();
    expect(find.text('업적 1 / 4'), findsOneWidget);
    expect(find.text('6/10'), findsOneWidget);
    await tester.tap(find.text('칭호 달기'));
    await tester.pumpAndSettle();
    expect(find.text('지금 칭호: 새내기 편지꾼'), findsOneWidget);
    expect(find.text('다는 중'), findsOneWidget);
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.text('새내기 편지꾼'), findsOneWidget);
  });

  testWidgets('편지지 보관함: 잠긴 편지지는 해금 조건', (tester) async {
    await openProfile(tester, rewards: (b, s) => FakeRewardsApi(b, s)..owned.add('lined'));
    expect(find.text('2/3'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('menu-stationery')));
    await tester.pumpAndSettle();
    expect(find.bySemanticsLabel('줄노트 편지지, 가지고 있어요'), findsOneWidget);
    expect(find.bySemanticsLabel('하늘 구름 편지지, 잠김, 10개 시를 방문하면 열려요'), findsOneWidget);
  });

  testWidgets('포인트 내역', (tester) async {
    await openProfile(tester, rewards: FakeRewardsApi.new);
    await tester.tap(find.byKey(const ValueKey('tile-attendance')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('좋아요!'));
    await tester.pumpAndSettle();
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('points-history')));
    await tester.pumpAndSettle();
    expect(find.text('출석 체크'), findsOneWidget);
    expect(find.text('+3P'), findsOneWidget);
  });
}
