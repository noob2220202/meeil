// 실기기 프레임 측정 (M7): 지도에 염소 N마리를 띄우고 이동·확대하면서 빌드/래스터 시간을 잰다.
//   flutter drive --profile --driver=test_driver/perf_driver.dart \
//     --target=integration_test/map_perf_test.dart [--dart-define=GOATS=60]
// 결과: build/map_frames.timeline_summary.json (90/99 퍼센타일, 놓친 프레임 수)
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:meeil/app/theme.dart';
import 'package:meeil/data/regions.dart';
import 'package:meeil/features/goats/schedule.dart';
import 'package:meeil/features/map/goat_painter.dart';
import 'package:meeil/features/map/map_geometry.dart';
import 'package:meeil/features/map/map_view.dart';

const goatCount = int.fromEnvironment('GOATS', defaultValue: 30);

/// 서버 없이 쓰는 결정적 가짜 일정: 염소마다 이웃 시를 따라 40분 머물고 50분 걷는다
GoatSchedule syntheticSchedule(RegionData data, DateTime now) {
  final rnd = math.Random(42);
  final codes = data.regions.map((r) => r.code).toList();
  const palette = [
    Color(0xFFE8505B),
    Color(0xFF3F8EFC),
    Color(0xFF3FBF9B),
    Color(0xFFF2B705),
    Color(0xFF9B6BDF),
    Color(0xFFF27BA0),
  ];
  final tracks = <String, GoatTrack>{};
  for (var g = 0; g < goatCount; g++) {
    var code = codes[rnd.nextInt(codes.length)];
    var t = now.subtract(Duration(minutes: rnd.nextInt(90)));
    final stops = <GoatStop>[];
    for (var i = 0; i < 40; i++) {
      final arrive = t;
      final depart = arrive.add(const Duration(minutes: 40));
      stops.add(GoatStop(regionCode: code, arriveAt: arrive, departAt: depart));
      final next = data.byCode[code]!.neighbors;
      code = next.isEmpty ? codes[rnd.nextInt(codes.length)] : next[rnd.nextInt(next.length)];
      t = depart.add(const Duration(minutes: 50));
    }
    tracks['g$g'] = GoatTrack(
      GoatInfo(
        id: 'g$g',
        kind: GoatKind.delivery,
        name: '염소$g',
        speedKmh: 50,
        look: GoatLook(hat: palette[g % palette.length], bag: const Color(0xFFF6C177)),
      ),
      stops,
    );
  }
  return GoatSchedule(
    tracks: tracks,
    clockOffset: Duration.zero,
    validUntil: now.add(const Duration(days: 1)),
    cityGoatLook: RollingLooks.city,
  );
}

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('지도 프레임: 염소 $goatCount마리 이동·확대', (tester) async {
    final data = RegionData.parse(await rootBundle.loadString('assets/map/regions.json'));
    final geo = MapGeometry.build(data);
    final now = DateTime.now();
    final schedule = syntheticSchedule(data, now);
    final controller = MapViewController();
    await tester.pumpWidget(
      MaterialApp(
        theme: buildTheme(),
        home: Scaffold(
          body: MapView(geo: geo, schedule: schedule, controller: controller),
        ),
      ),
    );
    await tester.pump(const Duration(seconds: 1));

    await binding.watchPerformance(() async {
      // 1) 가만히 5초(염소 뒤뚱)
      await tester.pump(const Duration(seconds: 5));
      // 2) 이리저리 끌기
      for (var i = 0; i < 4; i++) {
        await tester.fling(find.byType(MapView), Offset(i.isEven ? -300 : 300, 120), 900);
        await tester.pumpAndSettle(
          const Duration(milliseconds: 16),
          EnginePhase.sendSemanticsUpdate,
          const Duration(seconds: 3),
        );
      }
      // 3) 서울로 확대해 시 롤링 염소까지
      controller.focusRegion('11110');
      await tester.pump(const Duration(seconds: 3));
      await tester.fling(find.byType(MapView), const Offset(200, -200), 800);
      await tester.pump(const Duration(seconds: 3));
    }, reportKey: 'map_frames');
  });
}
