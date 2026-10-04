import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:meeil/data/regions.dart';

void main() {
  final data = RegionData.parse(File(regionAssetPath).readAsStringSync());

  test('번들 지역 데이터를 파싱한다', () {
    expect(data.version, '2026-07');
    expect(data.provinces.length, 16);
    expect(data.regions.length, 230);
    expect(data.provinceShapes.length, 16);
    expect(data.country, isNotEmpty);
    expect(data.byCode['47940']!.fullName, '경북 울릉군');
    expect(data.byCode['11110']!.fullName, '서울 종로구');
  });

  test('모든 대표점은 자기 지역 안에 있다', () {
    for (final r in data.regions) {
      expect(r.contains(r.centerLon, r.centerLat), isTrue, reason: r.fullName);
    }
  });

  group('기기에서 시 판정', () {
    final cases = {
      '서울시청': ([126.9780, 37.5665], '11140'),
      '광화문(종로구)': ([126.9769, 37.5759], '11110'),
      '수원역(일반구 → 수원시)': ([127.0016, 37.2659], '41110'),
      '해운대': ([129.1604, 35.1587], '26350'),
      '제주공항': ([126.4930, 33.5104], '50110'),
      '서귀포 중문': ([126.4128, 33.2483], '50130'),
      '세종청사': ([127.2890, 36.5040], '36110'),
      '울릉도 도동': ([130.9060, 37.4842], '47940'),
      '독도': ([131.8656, 37.2421], '47940'),
      '광주 상무지구(전남광주)': ([126.8513, 35.1531], '12240'),
    };
    cases.forEach((name, c) {
      test(name, () => expect(data.locate(c.$1[0], c.$1[1]), c.$2));
    });

    test('해안 바로 앞 바다(대략적 위치 오차)는 가까운 시로', () {
      // 해운대 해수욕장 앞 약 1km 바다
      expect(data.locate(129.1650, 35.1500), '26350');
    });

    test('대한민국 밖은 null', () {
      expect(data.locate(139.6917, 35.6895), isNull); // 도쿄
      expect(data.locate(125.7625, 39.0392), isNull); // 평양
      expect(data.locate(128.0, 33.0), isNull); // 남해 먼바다
    });
  });
}
