import 'dart:math' as math;
import 'dart:ui';

import '../../data/regions.dart';

/// 경위도 → 지도 평면 좌표(세계 좌표). 지도 SDK 없이 직접 그린다(SPEC 11.1).
///
/// - 등장방형 투영에 위도 36° 기준 cos 보정
/// - 울릉도·독도는 실제 위치가 너무 멀어 화면이 텅 비므로 서쪽으로 당겨 그린다(일러스트 지도 관례)
class MapProjection {
  const MapProjection();

  static const lat0 = 36.0;
  static const scale = 260.0; // 1° ≈ 260 세계 단위
  static const minLon = 124.4;
  static const maxLat = 38.75;

  /// 울릉군(독도 포함)을 당기는 양(경도)
  static const ulleungShiftLon = -0.95;
  static const ulleungCode = '47940';

  static final double _k = math.cos(lat0 * math.pi / 180);

  Offset project(double lon, double lat, {String? regionCode}) {
    final shift = regionCode == ulleungCode ? ulleungShiftLon : 0.0;
    return Offset((lon + shift - minLon) * _k * scale, (maxLat - lat) * scale);
  }

  /// 투영 전 경위도가 울릉 인셋 영역인지(나라 윤곽처럼 지역 코드가 없는 도형용)
  static bool isUlleungArea(double lon, double lat) => lon > 130.6 && lat > 37.0 && lat < 37.7;
}

/// 한 지역의 화면 도형
class RegionShape {
  RegionShape({
    required this.region,
    required this.path,
    required this.bounds,
    required this.center,
  });

  final Region region;
  final Path path;
  final Rect bounds;
  final Offset center;
}

class ProvinceGeo {
  ProvinceGeo({required this.code, required this.path, required this.label, required this.color});

  final String code;
  final Path path;
  final Offset label;
  final Color color;
}

/// 지도 전체 도형(한 번 만들고 캐시)
class MapGeometry {
  MapGeometry._({
    required this.data,
    required this.regions,
    required this.provinces,
    required this.country,
    required this.bounds,
    required this.ulleungInset,
  });

  final RegionData data;
  final Map<String, RegionShape> regions;
  final Map<String, ProvinceGeo> provinces;
  final Path country;
  final Rect bounds;

  /// 울릉·독도 인셋을 표시할 테두리
  final Rect ulleungInset;

  static const projection = MapProjection();

  /// 도별 파스텔(SPEC 12.3). 이웃한 도는 다른 색이 되도록 칠한다.
  static const provincePalette = [
    Color(0xFFFFE3A3), // 노랑
    Color(0xFFC6EBC9), // 민트
    Color(0xFFFFCFDB), // 분홍
    Color(0xFFD9CCF5), // 라벤더
    Color(0xFFFFD8B5), // 살구
    Color(0xFFBFE3F2), // 하늘(바다보다 진하게)
  ];

  Offset regionCenter(String code) => regions[code]?.center ?? Offset.zero;

  static Path _path(List<Polygon> polys, {String? regionCode, bool insetAware = false}) {
    final path = Path()..fillType = PathFillType.evenOdd;
    for (final poly in polys) {
      for (final ring in poly) {
        if (ring.length < 6) continue;
        String? code = regionCode;
        if (insetAware && MapProjection.isUlleungArea(ring[0], ring[1])) {
          code = MapProjection.ulleungCode;
        }
        final p0 = projection.project(ring[0], ring[1], regionCode: code);
        path.moveTo(p0.dx, p0.dy);
        for (var i = 2; i < ring.length; i += 2) {
          final p = projection.project(ring[i], ring[i + 1], regionCode: code);
          path.lineTo(p.dx, p.dy);
        }
        path.close();
      }
    }
    return path;
  }

  static MapGeometry build(RegionData data) {
    final regions = <String, RegionShape>{};
    var bounds = Rect.zero;
    for (final r in data.regions) {
      final path = _path(r.polygons, regionCode: r.code);
      final b = path.getBounds();
      bounds = bounds == Rect.zero ? b : bounds.expandToInclude(b);
      regions[r.code] = RegionShape(
        region: r,
        path: path,
        bounds: b,
        center: projection.project(r.centerLon, r.centerLat, regionCode: r.code),
      );
    }

    // 도 색칠: 시 이웃 관계로 도 인접 그래프를 만들고 탐욕적으로 칠한다(결정적)
    final adjacency = <String, Set<String>>{};
    for (final r in data.regions) {
      for (final n in r.neighbors) {
        final other = data.byCode[n]?.provinceCode;
        if (other != null && other != r.provinceCode) {
          adjacency.putIfAbsent(r.provinceCode, () => {}).add(other);
          adjacency.putIfAbsent(other, () => {}).add(r.provinceCode);
        }
      }
    }
    final colorIndex = <String, int>{};
    final codes = data.provinces.map((p) => p.code).toList()
      ..sort((a, b) => (adjacency[b]?.length ?? 0).compareTo(adjacency[a]?.length ?? 0));
    for (final code in codes) {
      final used = {for (final n in adjacency[code] ?? const <String>{}) colorIndex[n]};
      var c = 0;
      while (used.contains(c)) {
        c++;
      }
      colorIndex[code] = c % provincePalette.length;
    }

    final provinces = <String, ProvinceGeo>{
      for (final p in data.provinceShapes)
        p.code: ProvinceGeo(
          code: p.code,
          path: _path(p.polygons, insetAware: true),
          label: projection.project(p.labelLon, p.labelLat),
          color: provincePalette[colorIndex[p.code] ?? 0],
        ),
    };

    final ulleung = regions[MapProjection.ulleungCode]?.bounds ?? Rect.zero;
    return MapGeometry._(
      data: data,
      regions: regions,
      provinces: provinces,
      country: _path(data.country, insetAware: true),
      bounds: bounds.inflate(24),
      ulleungInset: ulleung.inflate(14),
    );
  }

  /// 세계 좌표의 점이 어느 시인지(지도 탭)
  String? hitTest(Offset world) {
    for (final shape in regions.values) {
      if (shape.bounds.contains(world) && shape.path.contains(world)) return shape.region.code;
    }
    return null;
  }
}
