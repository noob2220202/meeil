import 'dart:math' as math;

import 'package:flutter/rendering.dart';

import '../../app/theme.dart';
import 'goat_painter.dart';
import 'map_geometry.dart';

const _sea = Palette.sky;
const _border = Color(0xFFFFFFFF);
const _coast = Color(0xFF7A5C48);

/// 땅 레이어(세계 좌표). InteractiveViewer 안에서 함께 확대된다.
/// 선 굵기는 화면 픽셀 기준으로 유지하려고 [zoom]으로 나눈다.
class LandPainter extends CustomPainter {
  LandPainter({required this.geo, required this.zoom, this.myRegion, this.selectedRegion});

  final MapGeometry geo;

  /// 화면 px / 세계 단위
  final double zoom;
  final String? myRegion;
  final String? selectedRegion;

  static List<Offset>? _waveCache;
  static MapGeometry? _waveFor;

  /// 바다에 흩뿌릴 물결 위치(땅·인셋과 겹치지 않게, 결정적)
  List<Offset> _waves() {
    if (_waveFor == geo && _waveCache != null) return _waveCache!;
    final rnd = math.Random(7);
    final out = <Offset>[];
    final b = geo.bounds;
    for (var y = b.top + 30; y < b.bottom; y += 70) {
      for (var x = b.left + 20; x < b.right; x += 90) {
        final p = Offset(x + rnd.nextDouble() * 50, y + rnd.nextDouble() * 30);
        final nearLand =
            geo.country.contains(p) ||
            geo.country.contains(p + const Offset(26, 0)) ||
            geo.country.contains(p + const Offset(-14, 10)) ||
            geo.ulleungInset.inflate(10).contains(p);
        if (!nearLand) out.add(p);
      }
    }
    _waveFor = geo;
    return _waveCache = out;
  }

  @override
  void paint(Canvas canvas, Size size) {
    final px = 1 / zoom;
    canvas.translate(-geo.bounds.left, -geo.bounds.top);

    // 바다 물결
    final wave = Paint()
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeWidth = math.max(2.0, 2.2 * px)
      ..color = const Color(0xB3FFFFFF);
    for (final p in _waves()) {
      canvas.drawPath(
        Path()
          ..moveTo(p.dx, p.dy)
          ..quadraticBezierTo(p.dx + 6, p.dy - 6, p.dx + 12, p.dy)
          ..quadraticBezierTo(p.dx + 18, p.dy + 6, p.dx + 24, p.dy),
        wave,
      );
    }

    // 스티커처럼 살짝 띄운 그림자
    canvas.save();
    canvas.translate(4, 9);
    canvas.drawPath(geo.country, Paint()..color = const Color(0x2E5A4636));
    canvas.restore();

    // 도별 파스텔
    final fill = Paint()..style = PaintingStyle.fill;
    for (final p in geo.provinces.values) {
      fill.color = p.color;
      canvas.drawPath(p.path, fill);
    }

    // 내 시
    final mine = myRegion == null ? null : geo.regions[myRegion];
    if (mine != null) {
      canvas.drawPath(mine.path, fill..color = const Color(0xFFFFD45E));
    }

    // 시 경계(가는 흰 선) — 많이 축소했을 땐 흐리게
    final cityAlpha = ((zoom * 4.5) - 0.4).clamp(0.25, 1.0);
    final cityLine = Paint()
      ..style = PaintingStyle.stroke
      ..strokeJoin = StrokeJoin.round
      ..strokeWidth = 1.1 * px
      ..color = _border.withValues(alpha: cityAlpha);
    for (final r in geo.regions.values) {
      canvas.drawPath(r.path, cityLine);
    }

    // 도 경계(굵은 흰 선)
    final provinceLine = Paint()
      ..style = PaintingStyle.stroke
      ..strokeJoin = StrokeJoin.round
      ..strokeWidth = 2.6 * px
      ..color = _border;
    for (final p in geo.provinces.values) {
      canvas.drawPath(p.path, provinceLine);
    }

    // 해안선(갈색)
    canvas.drawPath(
      geo.country,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeJoin = StrokeJoin.round
        ..strokeWidth = 2.2 * px
        ..color = _coast,
    );

    // 선택한 시
    final sel = selectedRegion == null ? null : geo.regions[selectedRegion];
    if (sel != null) {
      canvas.drawPath(
        sel.path,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeJoin = StrokeJoin.round
          ..strokeWidth = 3.2 * px
          ..color = _coast,
      );
    }

    // 울릉·독도 인셋 테두리(실제보다 가깝게 그렸다는 표시)
    _dashedRRect(
      canvas,
      RRect.fromRectAndRadius(geo.ulleungInset, Radius.circular(10 * px + 6)),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.6 * px
        ..color = _coast.withValues(alpha: 0.55),
      dash: 7 * px + 3,
    );
  }

  void _dashedRRect(Canvas canvas, RRect rr, Paint paint, {required double dash}) {
    final path = Path()..addRRect(rr);
    for (final m in path.computeMetrics()) {
      for (var d = 0.0; d < m.length; d += dash * 2) {
        canvas.drawPath(m.extractPath(d, math.min(d + dash, m.length)), paint);
      }
    }
  }

  @override
  bool shouldRepaint(LandPainter old) =>
      old.geo != geo ||
      (old.zoom - zoom).abs() > zoom * 0.02 ||
      old.myRegion != myRegion ||
      old.selectedRegion != selectedRegion;
}

/// 화면에 그릴 염소 하나(세계 좌표 + 상태)
class GoatSprite {
  const GoatSprite({
    required this.id,
    required this.world,
    required this.look,
    required this.pose,
    required this.faceLeft,
    required this.phase,
    this.bySea = false,
    this.priority = 0,
    this.screenNudge = Offset.zero,
  });

  final String id;
  final Offset world;
  final GoatLook look;
  final GoatPose pose;
  final bool faceLeft;
  final double phase;
  final bool bySea;

  /// 클수록 위에 그린다(배달 > 도 > 전국 > 시)
  final int priority;

  /// 같은 곳에 여럿이 머물 때 겹치지 않게 화면에서 비켜 서는 양
  final Offset screenNudge;
}

/// 화면 좌표 레이어: 이름표, 염소, 내 위치 핀. 매 프레임 다시 그린다.
class OverlayPainter extends CustomPainter {
  OverlayPainter({
    required this.geo,
    required this.matrixOf,
    required this.fitZoom,
    required this.time,
    required this.sprites,
    required this.myRegion,
    required this.goatSizeOf,
    this.highlightGoat,
    super.repaint,
  });

  final MapGeometry geo;

  /// 세계(경계 원점 기준) → 화면 변환(매 프레임 최신 값)
  final Matrix4 Function() matrixOf;
  final double Function() goatSizeOf;
  late Matrix4 matrix;
  late double goatSize;

  /// 전국이 한 화면에 들어오는 배율
  final double fitZoom;
  final double Function() time;
  final List<GoatSprite> Function() sprites;
  final String? myRegion;
  final String? highlightGoat;

  static final Map<String, TextPainter> _labelCache = {};

  double get zoom => matrix.getMaxScaleOnAxis();
  double get relZoom => zoom / fitZoom;

  Offset toScreen(Offset world) {
    final local = world - geo.bounds.topLeft;
    return MatrixUtils.transformPoint(matrix, local);
  }

  @override
  void paint(Canvas canvas, Size size) {
    matrix = matrixOf();
    goatSize = goatSizeOf();
    final screen = Offset.zero & size;
    final t = time();
    _paintLabels(canvas, screen);
    _paintMyPin(canvas, screen, t);

    // 우선순위가 낮은 것, 위쪽(먼) 염소부터 그려야 가까운 염소가 앞에 온다
    final list = sprites()
      ..sort((a, b) {
        final p = a.priority.compareTo(b.priority);
        return p != 0 ? p : a.world.dy.compareTo(b.world.dy);
      });
    for (final s in list) {
      final at = toScreen(s.world) + s.screenNudge;
      if (!screen.inflate(goatSize).contains(at)) continue;
      if (s.bySea) _paintBoat(canvas, at, t + s.phase);
      GoatPainterKit.paint(
        canvas,
        at: s.bySea ? at.translate(0, -goatSize * 0.12) : at,
        size: goatSize,
        look: s.look,
        t: t,
        phase: s.phase,
        pose: s.bySea ? GoatPose.idle : s.pose,
        faceLeft: s.faceLeft,
        highlight: s.id == highlightGoat ? 1 : 0,
      );
    }
  }

  void _paintLabels(Canvas canvas, Rect screen) {
    final rz = relZoom;
    // 전국~도 배율: 시도 이름 / 더 확대하면 시 이름
    if (rz < 3.2) {
      final alpha = rz < 2.4 ? 1.0 : (3.2 - rz) / 0.8;
      for (final p in geo.provinces.values) {
        final name = geo.data.provinceByCode[p.code]?.shortName ?? '';
        _label(canvas, name, toScreen(p.label), 15, alpha, screen);
      }
    }
    if (rz >= 2.4) {
      final alpha = ((rz - 2.4) / 0.8).clamp(0.0, 1.0);
      for (final r in geo.regions.values) {
        final w = r.bounds.width * zoom;
        if (w < 46) continue;
        _label(canvas, r.region.name, toScreen(r.center).translate(0, 14), 12.5, alpha, screen);
      }
    }
  }

  void _label(Canvas canvas, String text, Offset at, double fontSize, double alpha, Rect screen) {
    if (alpha <= 0.01 || !screen.contains(at)) return;
    final key = '$text@$fontSize';
    final tp = _labelCache.putIfAbsent(key, () {
      return TextPainter(
        text: TextSpan(
          text: text,
          style: TextStyle(
            fontFamily: Fonts.title,
            fontSize: fontSize,
            color: Palette.textBrown,
            shadows: const [
              Shadow(color: Color(0xFFFFFFFF), blurRadius: 0, offset: Offset(1.2, 0)),
              Shadow(color: Color(0xFFFFFFFF), blurRadius: 0, offset: Offset(-1.2, 0)),
              Shadow(color: Color(0xFFFFFFFF), blurRadius: 0, offset: Offset(0, 1.2)),
              Shadow(color: Color(0xFFFFFFFF), blurRadius: 0, offset: Offset(0, -1.2)),
              Shadow(color: Color(0xFFFFFFFF), blurRadius: 3),
            ],
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
    });
    final pos = at - Offset(tp.width / 2, tp.height / 2);
    if (alpha >= 0.99) {
      tp.paint(canvas, pos);
    } else {
      canvas.saveLayer(pos & tp.size, Paint()..color = Color.fromRGBO(0, 0, 0, alpha));
      tp.paint(canvas, pos);
      canvas.restore();
    }
  }

  void _paintMyPin(Canvas canvas, Rect screen, double t) {
    final r = myRegion == null ? null : geo.regions[myRegion];
    if (r == null) return;
    final base = toScreen(r.center);
    if (!screen.inflate(40).contains(base)) return;
    final hop = -4 * math.sin(t * 3).abs();
    final tip = base.translate(0, hop);
    // 바닥 그림자
    canvas.drawOval(
      Rect.fromCenter(center: base, width: 14 + hop, height: 5),
      Paint()..color = const Color(0x405A4636),
    );
    final pin = Path()
      ..moveTo(tip.dx, tip.dy)
      ..cubicTo(tip.dx - 12, tip.dy - 14, tip.dx - 13, tip.dy - 32, tip.dx, tip.dy - 33)
      ..cubicTo(tip.dx + 13, tip.dy - 32, tip.dx + 12, tip.dy - 14, tip.dx, tip.dy)
      ..close();
    canvas.drawPath(pin, Paint()..color = const Color(0xFFFF8FAB));
    canvas.drawPath(
      pin,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.4
        ..color = _coast,
    );
    final tp = _labelCache.putIfAbsent(
      '나@pin',
      () => TextPainter(
        text: const TextSpan(
          text: '나',
          style: TextStyle(fontFamily: Fonts.title, fontSize: 12, color: Color(0xFFFFFFFF)),
        ),
        textDirection: TextDirection.ltr,
      )..layout(),
    );
    tp.paint(canvas, tip.translate(-tp.width / 2, -27));
  }

  /// 배·비행기 구간: 작은 배를 타고 둥실
  void _paintBoat(Canvas canvas, Offset at, double t) {
    final s = goatSize;
    final bob = 2 * math.sin(t * 2.2);
    final hull = Path()
      ..moveTo(at.dx - s * 0.48, at.dy - s * 0.12 + bob)
      ..lineTo(at.dx + s * 0.48, at.dy - s * 0.12 + bob)
      ..quadraticBezierTo(at.dx + s * 0.36, at.dy + s * 0.14 + bob, at.dx, at.dy + s * 0.14 + bob)
      ..quadraticBezierTo(
        at.dx - s * 0.36,
        at.dy + s * 0.14 + bob,
        at.dx - s * 0.48,
        at.dy - s * 0.12 + bob,
      )
      ..close();
    canvas.drawPath(hull, Paint()..color = const Color(0xFFC9893B));
    canvas.drawPath(
      hull,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.2
        ..color = _coast,
    );
    // 물보라
    final splash = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2
      ..strokeCap = StrokeCap.round
      ..color = const Color(0xCCFFFFFF);
    canvas.drawLine(
      at.translate(-s * 0.62, s * 0.08 + bob),
      at.translate(-s * 0.52, s * 0.02 + bob),
      splash,
    );
  }

  @override
  bool shouldRepaint(OverlayPainter old) => true;
}

/// 시드 문자열 → 0~1 (염소마다 다른 걸음 박자)
double phaseOf(String id) {
  var h = 0;
  for (final c in id.codeUnits) {
    h = (h * 31 + c) & 0x7fffffff;
  }
  return (h % 1000) / 1000;
}

const seaColor = _sea;
