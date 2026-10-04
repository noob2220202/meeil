import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:meeil/app/app.dart';
import 'package:meeil/app/router.dart';
import 'package:meeil/core/token_store.dart';
import 'package:meeil/features/goats/hand_availability.dart';
import 'package:meeil/features/location/my_region.dart';
import 'package:meeil/features/rolling/rolling_models.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/fakes.dart';

/// 주요 화면 접근성 점검 (M7): 터치 영역 48dp, 버튼 라벨, 글자 대비, 큰 글씨(200%)에서 넘침 없음
const screens = <String>[
  '/?tab=0',
  '/?tab=1',
  '/?tab=2',
  '/?tab=3',
  '/compose',
  '/letters/in-1',
  '/rolling/paper-city',
  '/rolling/album',
  '/attendance',
  '/achievements',
  '/stationery',
  '/points',
  '/settings',
  '/notices',
];

Future<void> open(WidgetTester tester, String path, {double textScale = 1}) async {
  tester.view.physicalSize = const Size(1080, 2400);
  tester.view.devicePixelRatio = 2.625;
  tester.platformDispatcher.textScaleFactorTestValue = textScale;
  tester.platformDispatcher.accessibilityFeaturesTestValue = const FakeAccessibilityFeatures(
    disableAnimations: true,
  );
  addTearDown(tester.view.reset);
  addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
  addTearDown(tester.platformDispatcher.clearAccessibilityFeaturesTestValue);
  SharedPreferences.setMockInitialValues({
    'flags.introSeen': true,
    'flags.permissionsIntroDone': true,
  });
  final backend = FakeBackend();
  final store = MemoryTokenStore()..tokens = backend.signedUp('접근성염소');
  final letters = FakeLettersApi(MemoryTokenStore())..inbox.add(sampleReceived(unread: false));
  final rolling = FakeRollingApi(MemoryTokenStore());
  rolling.views[RollingLevel.city] = FakeRollingApi.view(
    FakeRollingApi.paper(RollingLevel.city, topic: '오늘 먹은 맛있는 것'),
    canJoin: true,
    entries: [sampleEntry('e1', '콩이네', '떡볶이 최고!')],
  );
  rolling.views[RollingLevel.nation] = FakeRollingApi.view(
    FakeRollingApi.paper(RollingLevel.nation, scopeName: '전국'),
    block: JoinBlock.noGoatHere,
    next: fixtureNow.add(const Duration(hours: 20)),
  );
  final overrides = await appOverrides(
    backend: backend,
    store: store,
    letters: letters,
    rolling: rolling,
    location: FakeLocationSource(fix: const LocationFix(126.98, 37.57)),
  );
  await tester.pumpWidget(
    ProviderScope(
      overrides: [...overrides, clockTickProvider.overrideWith(() => FixedClock(fixtureNow))],
      child: const MeeilApp(),
    ),
  );
  await tester.pumpAndSettle();
  final c = ProviderScope.containerOf(tester.element(find.byType(MaterialApp)));
  final GoRouter router = c.read(routerProvider);
  if (path.startsWith('/?')) {
    router.go(path);
  } else {
    router.push(path);
  }
  await tester.pumpAndSettle();
}

void main() {
  for (final path in screens) {
    testWidgets('$path: 터치 영역·라벨·대비', (tester) async {
      final handle = tester.ensureSemantics();
      await open(tester, path);
      await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
      await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
      await expectLater(tester, meetsGuideline(textContrastGuideline));
      handle.dispose();
    });

    testWidgets('$path: 글자 200%에서 넘침 없음', (tester) async {
      await open(tester, path, textScale: 2);
      expect(tester.takeException(), isNull);
    });
  }
}
