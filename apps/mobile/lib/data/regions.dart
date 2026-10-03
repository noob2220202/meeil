import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// 시도
class Province {
  const Province({required this.code, required this.name, required this.shortName});

  final String code;
  final String name;
  final String shortName;
}

/// 시 단위 지역. 폴리곤은 [lon, lat, lon, lat, ...] 평면 배열 링의 목록.
class Region {
  const Region({
    required this.code,
    required this.name,
    required this.fullName,
    required this.provinceCode,
    required this.centerLon,
    required this.centerLat,
    required this.neighbors,
    required this.polygons,
  });

  final String code;
  final String name;
  final String fullName;
  final String provinceCode;
  final double centerLon;
  final double centerLat;
  final List<String> neighbors;

  /// polygons[i][0]은 외곽 링, 나머지는 구멍
  final List<List<Float64List>> polygons;
}

class RegionData {
  RegionData({required this.version, required this.provinces, required this.regions})
      : byCode = {for (final r in regions) r.code: r};

  final String version;
  final List<Province> provinces;
  final List<Region> regions;
  final Map<String, Region> byCode;

  static RegionData parse(String source) {
    final json = jsonDecode(source) as Map<String, dynamic>;
    final provinces = [
      for (final p in json['provinces'] as List)
        Province(
          code: p['code'] as String,
          name: p['name'] as String,
          shortName: p['shortName'] as String,
        ),
    ];
    final regions = [
      for (final r in json['regions'] as List)
        Region(
          code: r['code'] as String,
          name: r['name'] as String,
          fullName: r['fullName'] as String,
          provinceCode: r['provinceCode'] as String,
          centerLon: (r['center'][0] as num).toDouble(),
          centerLat: (r['center'][1] as num).toDouble(),
          neighbors: (r['neighbors'] as List).cast<String>(),
          polygons: [
            for (final poly in r['polygons'] as List)
              [
                for (final ring in poly as List)
                  Float64List.fromList([for (final v in ring as List) (v as num).toDouble()]),
              ],
          ],
        ),
    ];
    return RegionData(version: json['version'] as String, provinces: provinces, regions: regions);
  }
}

const regionAssetPath = 'assets/map/regions.json';

/// 번들된 지역 경계 데이터. 파싱은 별도 isolate에서.
final regionDataProvider = FutureProvider<RegionData>((ref) async {
  final source = await rootBundle.loadString(regionAssetPath);
  return compute(RegionData.parse, source);
});
