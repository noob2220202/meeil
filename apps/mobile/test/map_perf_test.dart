import 'dart:ui';

import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:meeil/features/goats/schedule.dart';
import 'package:meeil/features/map/goat_scene.dart';
import 'package:meeil/features/map/map_geometry.dart';
import 'package:meeil/features/map/map_painters.dart';

import 'support/fakes.dart';

/// 한 프레임에 염소·이름표를 그리는 데 드는 Dart 쪽 비용(그리기 명령 기록)을 잰다.
/// GPU 래스터 비용은 실기기에서 `flutter run --profile`로 확인한다(docs/DECISIONS.md).
void main() {
  final geo = MapGeometry.build(testRegionData);
  final schedule = loadScheduleFixture();

  double measure({
    required double relZoom,
    required Rect visible,
    int frames = 120,
    GoatSchedule? schedule,
  }) {
    final sched = schedule ?? loadScheduleFixture();
    const size = Size(412, 860);
    final fit = 412 / geo.bounds.width;
    final zoom = fit * relZoom;
    // 보이는 창의 왼쪽 위가 화면 원점에 오도록
    final origin = visible.topLeft - geo.bounds.topLeft;
    final matrix = Matrix4.identity()
      ..scaleByDouble(zoom, zoom, 1, 1)
      ..translateByDouble(-origin.dx, -origin.dy, 0, 1);
    final sw = Stopwatch();
    for (var f = 0; f < frames + 10; f++) {
      final t = f / 60;
      final painter = OverlayPainter(
        geo: geo,
        matrixOf: () => matrix,
        fitZoom: fit,
        time: () => t,
        sprites: () => buildGoatSprites(
          geo: geo,
          schedule: sched,
          now: fixtureNow.add(Duration(milliseconds: (t * 1000).round())),
          t: t,
          relZoom: relZoom,
          visibleWorld: visible,
          goatSize: 40,
        ),
        myRegion: '11110',
        goatSizeOf: () => 40,
      );
      if (f == 10) sw.start(); // 워밍업 뒤부터
      final rec = PictureRecorder();
      painter.paint(Canvas(rec), size);
      rec.endRecording().dispose();
    }
    sw.stop();
    return sw.elapsedMicroseconds / frames / 1000;
  }

  test('전국 보기 29마리: 한 프레임 기록 비용', () {
    final ms = measure(relZoom: 1, visible: geo.bounds);
    // ignore: avoid_print
    print('전국 보기 프레임당 ${ms.toStringAsFixed(2)}ms (디버그 JIT)');
    // 60fps 예산 16.7ms 중 래스터에 충분한 여유를 남긴다(디버그 모드라 실제보다 느리다)
    expect(ms, lessThan(8));
  });

  test('시 확대 보기(시 롤링 염소 포함)', () {
    // 서울 전체가 보이는 넓은 창: 시 롤링 염소 25마리 + 지나가는 염소들
    final seoul = geo.provinces['11']!.path.getBounds();
    final sprites = buildGoatSprites(
      geo: geo,
      schedule: schedule,
      now: fixtureNow,
      t: 0,
      relZoom: 6,
      visibleWorld: seoul,
      goatSize: 40,
    );
    // ignore: avoid_print
    print('확대 보기 염소 ${sprites.length}마리');
    expect(sprites.length, greaterThanOrEqualTo(25 + 12));
    final ms = measure(relZoom: 6, visible: seoul);
    // ignore: avoid_print
    print('확대 보기 프레임당 ${ms.toStringAsFixed(2)}ms (디버그 JIT)');
    expect(ms, lessThan(8));
  });

  test('스트레스: 염소 두 배(전국 58마리 이상)도 예산 안', () {
    // 실제보다 많은 염소: 모든 일정을 30분 늦춘 복제본을 더한다
    final doubled = GoatSchedule(
      tracks: {
        ...schedule.tracks,
        for (final e in schedule.tracks.entries)
          '${e.key}-copy': GoatTrack(
            GoatInfo(
              id: '${e.value.goat.id}-copy',
              kind: e.value.goat.kind,
              name: e.value.goat.name,
              speedKmh: e.value.goat.speedKmh,
              look: e.value.goat.look,
              scopeCode: e.value.goat.scopeCode,
            ),
            [
              for (final st in e.value.stops)
                GoatStop(
                  regionCode: st.regionCode,
                  arriveAt: st.arriveAt.add(const Duration(minutes: 30)),
                  departAt: st.departAt.add(const Duration(minutes: 30)),
                  bySea: st.bySea,
                ),
            ],
          ),
      },
      clockOffset: Duration.zero,
      validUntil: schedule.validUntil,
      cityGoatLook: schedule.cityGoatLook,
    );
    final sprites = buildGoatSprites(
      geo: geo,
      schedule: doubled,
      now: fixtureNow,
      t: 0,
      relZoom: 1,
      visibleWorld: geo.bounds,
      goatSize: 40,
    );
    // ignore: avoid_print
    print('스트레스 전국 염소 ${sprites.length}마리');
    expect(sprites.length, greaterThanOrEqualTo(50));
    final ms = measure(relZoom: 1, visible: geo.bounds, schedule: doubled);
    // ignore: avoid_print
    print('스트레스 프레임당 ${ms.toStringAsFixed(2)}ms (디버그 JIT)');
    expect(ms, lessThan(10));
  });

  test('땅 레이어(확대 배율이 바뀔 때만 다시 그림)', () {
    final sw = Stopwatch()..start();
    for (var i = 0; i < 20; i++) {
      final rec = PictureRecorder();
      LandPainter(
        geo: geo,
        zoom: 0.3 + i * 0.05,
        myRegion: '11110',
      ).paint(Canvas(rec), geo.bounds.size);
      rec.endRecording().dispose();
    }
    final ms = sw.elapsedMicroseconds / 20 / 1000;
    // ignore: avoid_print
    print('땅 레이어 ${ms.toStringAsFixed(2)}ms');
    expect(ms, lessThan(16));
  });
}
