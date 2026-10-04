import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// 폴리곤 하나: [0]은 외곽 링, 나머지는 구멍. 링은 [lon, lat, lon, lat, ...]
typedef Polygon = List<Float64List>;

/// 시도
class Province {
  const Province({required this.code, required this.name, required this.shortName});

  final String code;
  final String name;
  final String shortName;
}

/// 지도용 시도 윤곽과 이름표 위치
class ProvinceShape {
  const ProvinceShape({
    required this.code,
    required this.labelLon,
    required this.labelLat,
    required this.polygons,
  });

  final String code;
  final double labelLon;
  final double labelLat;
  final List<Polygon> polygons;
}

/// 시 단위 지역
class Region {
  Region({
    required this.code,
    required this.name,
    required this.fullName,
    required this.provinceCode,
    required this.centerLon,
    required this.centerLat,
    required this.neighbors,
    required this.polygons,
  }) : bbox = _bbox(polygons);

  final String code;
  final String name;
  final String fullName;
  final String provinceCode;
  final double centerLon;
  final double centerLat;
  final List<String> neighbors;
  final List<Polygon> polygons;

  /// [minLon, minLat, maxLon, maxLat]
  final List<double> bbox;

  static List<double> _bbox(List<Polygon> polygons) {
    var minX = double.infinity, minY = double.infinity;
    var maxX = -double.infinity, maxY = -double.infinity;
    for (final poly in polygons) {
      final ring = poly.first;
      for (var i = 0; i < ring.length; i += 2) {
        minX = math.min(minX, ring[i]);
        maxX = math.max(maxX, ring[i]);
        minY = math.min(minY, ring[i + 1]);
        maxY = math.max(maxY, ring[i + 1]);
      }
    }
    return [minX, minY, maxX, maxY];
  }

  /// 점이 이 지역 안에 있는지(구멍 제외)
  bool contains(double lon, double lat) {
    if (lon < bbox[0] || lon > bbox[2] || lat < bbox[1] || lat > bbox[3]) return false;
    for (final poly in polygons) {
      if (!pointInRing(lon, lat, poly.first)) continue;
      var inHole = false;
      for (var h = 1; h < poly.length; h++) {
        if (pointInRing(lon, lat, poly[h])) {
          inHole = true;
          break;
        }
      }
      if (!inHole) return true;
    }
    return false;
  }
}

/// 짝수-홀수 규칙 point-in-polygon
bool pointInRing(double x, double y, Float64List ring) {
  var inside = false;
  final n = ring.length ~/ 2;
  for (var i = 0, j = n - 1; i < n; j = i++) {
    final xi = ring[2 * i], yi = ring[2 * i + 1];
    final xj = ring[2 * j], yj = ring[2 * j + 1];
    if ((yi > y) != (yj > y) && x < (xj - xi) * (y - yi) / (yj - yi) + xi) inside = !inside;
  }
  return inside;
}

/// 두 경위도 점 사이 거리(km)
double haversineKm(double lon1, double lat1, double lon2, double lat2) {
  const r = 6371.0;
  const rad = math.pi / 180;
  final dLat = (lat2 - lat1) * rad;
  final dLon = (lon2 - lon1) * rad;
  final h =
      math.pow(math.sin(dLat / 2), 2) +
      math.cos(lat1 * rad) * math.cos(lat2 * rad) * math.pow(math.sin(dLon / 2), 2);
  return 2 * r * math.asin(math.sqrt(h));
}

class RegionData {
  RegionData({
    required this.version,
    required this.provinces,
    required this.regions,
    this.provinceShapes = const [],
    this.country = const [],
  }) : byCode = {for (final r in regions) r.code: r},
       provinceByCode = {for (final p in provinces) p.code: p};

  final String version;
  final List<Province> provinces;
  final List<Region> regions;
  final List<ProvinceShape> provinceShapes;
  final List<Polygon> country;
  final Map<String, Region> byCode;
  final Map<String, Province> provinceByCode;

  /// 해안 근처의 대략적 위치는 바다로 찍힐 수 있으므로, 이 거리 안이면 가장 가까운 시로 본다
  static const coastSnapKm = 15.0;

  /// 기기에서 시를 판정한다(SPEC 8). 대한민국 밖이면 null.
  String? locate(double lon, double lat) {
    for (final r in regions) {
      if (r.contains(lon, lat)) return r.code;
    }
    Region? best;
    var bestKm = double.infinity;
    for (final r in regions) {
      final km = haversineKm(lon, lat, r.centerLon, r.centerLat);
      if (km < bestKm) {
        bestKm = km;
        best = r;
      }
    }
    // 대표점까지 거리가 아니라 경계까지 거리가 중요하므로 넉넉히(대표점 기준 +25km) 본다
    if (best != null && bestKm <= coastSnapKm + 25 && _nearEdge(best, lon, lat)) return best.code;
    return null;
  }

  bool _nearEdge(Region r, double lon, double lat) {
    const pad = 0.15; // 약 15km
    return lon >= r.bbox[0] - pad &&
        lon <= r.bbox[2] + pad &&
        lat >= r.bbox[1] - pad &&
        lat <= r.bbox[3] + pad;
  }

  static List<Polygon> _polys(Object? raw) => [
    for (final poly in (raw as List? ?? const []))
      [
        for (final ring in poly as List)
          Float64List.fromList([for (final v in ring as List) (v as num).toDouble()]),
      ],
  ];

  static RegionData parse(String source) {
    final json = jsonDecode(source) as Map<String, dynamic>;
    return RegionData(
      version: json['version'] as String,
      provinces: [
        for (final p in json['provinces'] as List)
          Province(
            code: p['code'] as String,
            name: p['name'] as String,
            shortName: p['shortName'] as String,
          ),
      ],
      regions: [
        for (final r in json['regions'] as List)
          Region(
            code: r['code'] as String,
            name: r['name'] as String,
            fullName: r['fullName'] as String,
            provinceCode: r['provinceCode'] as String,
            centerLon: (r['center'][0] as num).toDouble(),
            centerLat: (r['center'][1] as num).toDouble(),
            neighbors: (r['neighbors'] as List).cast<String>(),
            polygons: _polys(r['polygons']),
          ),
      ],
      provinceShapes: [
        for (final p in json['provinceShapes'] as List? ?? const [])
          ProvinceShape(
            code: p['code'] as String,
            labelLon: (p['label'][0] as num).toDouble(),
            labelLat: (p['label'][1] as num).toDouble(),
            polygons: _polys(p['polygons']),
          ),
      ],
      country: _polys(json['country']),
    );
  }
}

const regionAssetPath = 'assets/map/regions.json';

/// 번들된 지역 경계 데이터. 파싱은 별도 isolate에서.
final regionDataProvider = FutureProvider<RegionData>((ref) async {
  final source = await rootBundle.loadString(regionAssetPath);
  return compute(RegionData.parse, source);
});
