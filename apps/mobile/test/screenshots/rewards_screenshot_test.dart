@Tags(['screenshot'])
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:meeil/app/app.dart';
import 'package:meeil/core/token_store.dart';
import 'package:meeil/features/rewards/rewards_models.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../support/fakes.dart';
import 'screenshot_helper.dart';

FakeRewardsApi? _api;

Future<Widget> app({void Function(FakeRewardsApi api)? setup, int points = 12}) async {
  SharedPreferences.setMockInitialValues({
    'flags.introSeen': true,
    'flags.permissionsIntroDone': true,
  });
  final backend = FakeBackend();
  final store = MemoryTokenStore()..tokens = backend.signedUp('풀뜯기', points: points);
  final api = FakeRewardsApi(backend, store)
    ..streak = 3
    ..days.addAll(['2026-10-01', '2026-10-02', '2026-09-30', '2026-10-01'])
    ..adToday = 2;
  setup?.call(api);
  _api = api;
  final overrides = await appOverrides(backend: backend, store: store, rewards: api);
  return ProviderScope(overrides: overrides, child: const MeeilApp());
}

Future<void> profile(WidgetTester t) async {
  await t.tap(find.text('내 정보'));
  await t.pumpAndSettle();
}

void main() {
  testWidgets('M5 포인트·출석·업적 화면들', (tester) async {
    await tester.runAsync(loadAppFonts);

    await captureScreen(tester, await app(), 'm5_01_profile', beforeCapture: profile);

    await captureScreen(
      tester,
      await app(),
      'm5_02_attendance_dialog',
      beforeCapture: (t) async {
        await profile(t);
        await t.tap(find.byKey(const ValueKey('tile-attendance')));
      },
    );

    await captureScreen(
      tester,
      await app(),
      'm5_03_attendance_calendar',
      beforeCapture: (t) async {
        await profile(t);
        await t.tap(find.byKey(const ValueKey('tile-attendance')));
        await t.pumpAndSettle();
        await t.tap(find.text('좋아요!'));
      },
    );

    await captureScreen(
      tester,
      await app(setup: (a) => a.owned.add('lined')),
      'm5_04_achievements',
      beforeCapture: (t) async {
        await profile(t);
        await t.tap(find.byKey(const ValueKey('menu-achievements')));
        await t.pumpAndSettle();
        await t.tap(find.text('칭호 달기'));
      },
    );

    await captureScreen(
      tester,
      await app(
        setup: (a) => a.pending.add(
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
      ),
      'm5_05_achievement_unlocked',
    );

    await captureScreen(
      tester,
      await app(setup: (a) => a.owned.add('lined')),
      'm5_06_stationery',
      beforeCapture: (t) async {
        await profile(t);
        await t.tap(find.byKey(const ValueKey('menu-stationery')));
      },
    );

    await captureScreen(
      tester,
      await app(),
      'm5_07_points_history',
      beforeCapture: (t) async {
        await profile(t);
        await t.tap(find.byKey(const ValueKey('tile-ad')));
        await t.pumpAndSettle();
        await t.tap(find.text('좋아요!'));
        await t.pumpAndSettle();
        await t.tap(find.byKey(const ValueKey('tile-attendance')));
        await t.pumpAndSettle();
        await t.tap(find.text('좋아요!'));
        await t.pumpAndSettle();
        await t.binding.handlePopRoute();
        await t.pumpAndSettle();
        await t.tap(find.byKey(const ValueKey('points-history')));
      },
    );
    expect(_api, isNotNull);
  });
}
