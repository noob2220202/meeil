import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:meeil/data/regions.dart';

void main() {
  test('번들 지역 데이터를 파싱한다', () {
    final data = RegionData.parse(File(regionAssetPath).readAsStringSync());
    expect(data.version, '2026-07');
    expect(data.provinces.length, 16);
    expect(data.regions.length, greaterThanOrEqualTo(220));
    for (final r in data.regions) {
      expect(r.polygons, isNotEmpty, reason: r.fullName);
      for (final poly in r.polygons) {
        for (final ring in poly) {
          expect(ring.length.isEven, isTrue);
          expect(ring.length, greaterThanOrEqualTo(6));
        }
      }
    }
    expect(data.byCode['47940']!.fullName, '경북 울릉군');
    expect(data.byCode['11110']!.fullName, '서울 종로구');
  });
}
