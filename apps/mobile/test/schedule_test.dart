import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:meeil/features/goats/goat_texts.dart';
import 'package:meeil/features/goats/schedule.dart';
import 'package:meeil/features/location/my_region.dart';
import 'package:meeil/features/map/goat_painter.dart';
import 'package:meeil/features/map/goat_scene.dart';
import 'package:meeil/features/map/map_geometry.dart';

import 'support/fakes.dart';

GoatTrack track(List<GoatStop> stops) => GoatTrack(
  const GoatInfo(
    id: 'g',
    kind: GoatKind.delivery,
    name: '메롱이',
    speedKmh: 70,
    look: GoatLook(hat: Color(0xFFE8505B), bag: Color(0xFFF6C177)),
  ),
  stops,
);

DateTime at(int h, [int m = 0]) => DateTime.utc(2026, 10, 3, h, m);

void main() {
  final t = track([
    GoatStop(regionCode: 'A', arriveAt: at(1), departAt: at(2)),
    GoatStop(regionCode: 'B', arriveAt: at(3), departAt: at(4), bySea: true),
  ]);

  group('GoatTrack.at', () {
    test('첫 정류 전·마지막 출발 뒤는 모름', () {
      expect(t.at(at(0)), isA<GoatUnknown>());
      expect(t.at(at(5)), isA<GoatUnknown>());
    });
    test('머무는 중', () {
      final m = t.at(at(1, 30));
      expect(m, isA<GoatStaying>());
      expect((m as GoatStaying).stop.regionCode, 'A');
      expect(m.next!.regionCode, 'B');
    });
    test('이동 중 진행률', () {
      final m = t.at(at(2, 30)) as GoatTraveling;
      expect(m.from.regionCode, 'A');
      expect(m.to.regionCode, 'B');
      expect(m.progress, closeTo(0.5, 1e-9));
      expect(m.to.bySea, isTrue);
    });
    test('경계 시각: 도착 순간은 머무는 중, 출발 순간은 이동 중', () {
      expect(t.at(at(3)), isA<GoatStaying>());
      expect(t.at(at(2)), isA<GoatTraveling>());
    });
  });

  test('이동 보간은 양 끝을 지나고 단조 증가한다', () {
    const a = Offset(0, 0), b = Offset(100, 0);
    expect(lerpTravel(a, b, 0), a);
    expect(lerpTravel(a, b, 1), b);
    var prev = -1.0;
    for (var p = 0.0; p <= 1.0; p += 0.05) {
      final x = lerpTravel(a, b, p).dx;
      expect(x, greaterThanOrEqualTo(prev));
      prev = x;
    }
  });

  test('머무는 염소 어슬렁: 제자리로 돌아오고, 걷는 동안만 걷기 자세', () {
    expect(strollAt(0, 0).dx, 0);
    expect(strollAt(4, 0).walking, isTrue);
    expect(strollAt(4, 0).faceLeft, isFalse);
    expect(strollAt(8, 0).faceLeft, isTrue);
    expect(strollAt(8.999, 0).dx, closeTo(0, 0.1));
    expect(strollAt(1, 0).walking, isFalse);
  });

  test('시계는 기기 시간대와 무관하게 KST', () {
    expect(formatClock(DateTime.utc(2026, 10, 3, 3, 5)), '오후 12:05');
    expect(formatClock(DateTime.utc(2026, 10, 3, 15, 0)), '오전 12:00');
    expect(formatClock(DateTime.utc(2026, 10, 3, 6, 30)), '오후 3:30');
  });

  test('남은 시간·시계 표기', () {
    expect(formatRemaining(const Duration(seconds: 20)), '곧');
    expect(formatRemaining(const Duration(minutes: 45)), '45분');
    expect(formatRemaining(const Duration(hours: 3)), '3시간');
    expect(formatRemaining(const Duration(hours: 3, minutes: 20)), '3시간 20분');
  });

  group('실제 서버 스케줄 픽스처', () {
    final schedule = loadScheduleFixture();
    final data = testRegionData;
    final geo = MapGeometry.build(data);

    test('29마리 모두 지금 위치를 안다', () {
      expect(schedule.tracks, hasLength(29));
      for (final tr in schedule.tracks.values) {
        expect(tr.at(fixtureNow), isNot(isA<GoatUnknown>()), reason: tr.goat.id);
      }
    });

    test('모든 시에 48시간 안에 배달 염소가 온다(앱은 48시간치를 받는다)', () {
      for (final r in data.regions) {
        final next = schedule.nextDeliveryTo(r.code, fixtureNow);
        expect(next, isNotNull, reason: r.fullName);
        expect(next!.$2.difference(fixtureNow), lessThanOrEqualTo(const Duration(hours: 48)));
      }
    });

    test('지도 염소 목록: 전국 보기에선 29마리, 시로 줌인하면 시 롤링 염소도', () {
      final nation = buildGoatSprites(
        geo: geo,
        schedule: schedule,
        now: fixtureNow,
        t: 0,
        relZoom: 1,
        visibleWorld: geo.bounds,
        goatSize: 40,
      );
      expect(nation, hasLength(29));
      final zoomed = buildGoatSprites(
        geo: geo,
        schedule: schedule,
        now: fixtureNow,
        t: 0,
        relZoom: cityGoatRelZoom,
        visibleWorld: geo.regions['11110']!.bounds.inflate(40),
        goatSize: 40,
      );
      expect(zoomed.where((s) => s.id.startsWith(cityGoatPrefix)), isNotEmpty);
    });

    test('안내 배너: 위치 없음 / 염소 와 있음 / 다음 염소', () {
      expect(
        mapBanner(
          my: const MyRegionState(status: MyRegionStatus.denied),
          schedule: schedule,
          data: data,
          now: fixtureNow,
        ).action,
        '위치 켜기',
      );
      // 지금 배달 염소가 머무는 시 하나를 골라 본다
      final staying = schedule.tracks.values
          .where((tr) => tr.goat.kind == GoatKind.delivery)
          .map((tr) => tr.at(fixtureNow))
          .whereType<GoatStaying>()
          .first;
      final here = mapBanner(
        my: MyRegionState(status: MyRegionStatus.ok, regionCode: staying.stop.regionCode),
        schedule: schedule,
        data: data,
        now: fixtureNow,
      );
      expect(here.title, '우체부 염소가 왔어요!');
      expect(here.tone, BannerTone.arrived);

      final empty = data.regions
          .map((r) => r.code)
          .firstWhere((c) => schedule.deliveryGoatsIn(c, fixtureNow).isEmpty);
      final wait = mapBanner(
        my: MyRegionState(status: MyRegionStatus.ok, regionCode: empty),
        schedule: schedule,
        data: data,
        now: fixtureNow,
      );
      expect(wait.title, startsWith('다음 염소 '));
      expect(wait.tone, BannerTone.waiting);
    });

    test('염소 상태 문구', () {
      for (final tr in schedule.tracks.values) {
        final line = goatStatusLine(tr.at(fixtureNow), data, fixtureNow);
        expect(line, anyOf(contains('쉬는 중'), contains('도착')), reason: tr.goat.id);
      }
    });
  });
}
