@Tags(['screenshot'])
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:meeil/app/app.dart';
import 'package:meeil/app/theme.dart';
import 'package:meeil/core/token_store.dart';
import 'package:meeil/features/goats/goat_sheet.dart';
import 'package:meeil/features/goats/schedule.dart';
import 'package:meeil/features/home/main_shell.dart';
import 'package:meeil/features/location/my_region.dart';
import 'package:meeil/features/map/goat_scene.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../support/fakes.dart';
import 'screenshot_helper.dart';

Widget app(Widget home, List overrides) => ProviderScope(
  overrides: [...overrides],
  child: MaterialApp(
    theme: buildTheme(),
    debugShowCheckedModeBanner: false,
    locale: appLocale,
    supportedLocales: const [appLocale],
    localizationsDelegates: appLocalizationsDelegates,
    home: home,
  ),
);

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('M2 지도', (tester) async {
    await tester.runAsync(loadAppFonts);
    final schedule = loadScheduleFixture();
    final data = testRegionData;

    // 지금 배달 염소가 머무는 시에 "내"가 있다고 가정(도착 배너가 보이게)
    final stayingTrack = schedule.tracks.values.firstWhere(
      (tr) => tr.goat.kind == GoatKind.delivery && tr.at(fixtureNow) is GoatStaying,
    );
    final staying = stayingTrack.at(fixtureNow) as GoatStaying;
    final home = data.byCode[staying.stop.regionCode]!;

    Future<List> overrides() async => appOverrides(
      backend: FakeBackend(),
      store: MemoryTokenStore(),
      location: FakeLocationSource(fix: LocationFix(home.centerLon, home.centerLat)),
    );

    await captureScreen(
      tester,
      app(MainShell(mapClock: () => fixtureNow), await overrides()),
      'm2_01_map_nation',
    );
    await captureScreen(
      tester,
      app(MainShell(mapClock: () => fixtureNow), await overrides()),
      'm2_02_map_my_city',
      beforeCapture: (t) async {
        await t.tap(find.bySemanticsLabel('내 위치'));
        await t.pumpAndSettle();
        // 화면 가운데(내 시) 탭 → 지역 카드
        final size = t.view.physicalSize / t.view.devicePixelRatio;
        await t.tapAt(Offset(size.width / 2, size.height * 0.5));
      },
    );
    await captureScreen(
      tester,
      app(MainShell(mapClock: () => fixtureNow), [
        ...await appOverrides(backend: FakeBackend(), store: MemoryTokenStore()),
      ]),
      'm2_03_map_no_location',
      beforeCapture: (t) async {},
    );

    // 염소 상세: 이동 중인 배달 염소 / 머무는 염소 / 시 롤링 염소
    final traveling = schedule.tracks.values.firstWhere((tr) => tr.at(fixtureNow) is GoatTraveling);
    for (final (name, ref) in [
      ('m2_04_goat_traveling', ScheduledGoatRef(traveling.goat.id) as GoatRef),
      ('m2_05_goat_staying', ScheduledGoatRef(stayingTrack.goat.id) as GoatRef),
      ('m2_06_goat_city', const CityGoatRef('11110') as GoatRef),
    ]) {
      await captureScreen(
        tester,
        app(
          Scaffold(
            backgroundColor: Palette.sky,
            body: Align(
              alignment: Alignment.bottomCenter,
              child: Material(
                color: Palette.cream,
                shape: const RoundedRectangleBorder(
                  borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
                  side: BorderSide(color: Palette.outline, width: 2.5),
                ),
                child: Padding(
                  padding: const EdgeInsets.only(top: 24),
                  child: GoatSheet(
                    goatRef: ref,
                    schedule: schedule,
                    data: data,
                    clock: () => fixtureNow,
                  ),
                ),
              ),
            ),
          ),
          await overrides(),
        ),
        name,
      );
    }
  });
}
