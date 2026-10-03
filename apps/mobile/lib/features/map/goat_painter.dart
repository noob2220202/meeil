import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter/painting.dart';

/// 염소 겉모습(색 토큰). 12마리 배달 염소 + 롤링 3색을 이 값만 바꿔 그린다(SPEC 12.2).
class GoatLook {
  const GoatLook({required this.hat, required this.bag, this.scroll = false});

  final Color hat;
  final Color bag;

  /// 롤링 염소는 등에 두루마리를 진다
  final bool scroll;
}

enum GoatPose { walk, idle }

const _outline = Color(0xFF7A5C48);
const _white = Color(0xFFFFFFFF);
const _shade = Color(0xFFEDE6DD);
const _horn = Color(0xFFF3E3C3);
const _innerEar = Color(0xFFFFC9D6);
const _blush = Color(0xD9FFB3C4);
const _eye = Color(0xFF3B2A20);
const _hoof = Color(0xFF8C6A55);
const _muzzle = Color(0xFFFFF3E6);
const _paper = Color(0xFFFFF8EC);

/// 염소 한 마리를 그린다. [at]은 발바닥 가운데, [size]는 그림 전체 높이(논리 px).
/// 모든 움직임은 [t](초)로부터 계산되므로 같은 t면 같은 그림이 나온다.
class GoatPainterKit {
  GoatPainterKit._();

  // 로컬 좌표: 120x120 상자, 오른쪽을 본다. 발바닥 = (60, 104)
  static const double _box = 120;
  static const Offset _feet = Offset(60, 104);

  static final Paint _stroke = Paint()
    ..style = PaintingStyle.stroke
    ..color = _outline
    ..strokeWidth = 4.2
    ..strokeJoin = StrokeJoin.round
    ..strokeCap = StrokeCap.round;
  static final Paint _fill = Paint()..style = PaintingStyle.fill;

  static final Path _body = Path()
    ..addRRect(
      RRect.fromRectAndRadius(const Rect.fromLTRB(26, 58, 82, 94), const Radius.circular(18)),
    );
  static final Path _leg = Path()
    ..addRRect(
      RRect.fromRectAndRadius(const Rect.fromLTRB(-5, 0, 5, 18), const Radius.circular(5)),
    );
  static final Path _hoofPath = Path()
    ..addRRect(
      RRect.fromRectAndRadius(const Rect.fromLTRB(-5, 13, 5, 18), const Radius.circular(3)),
    );
  static final Path _tail = Path()
    ..moveTo(28, 64)
    ..quadraticBezierTo(16, 56, 20, 48)
    ..quadraticBezierTo(28, 54, 30, 62)
    ..close();
  static final Path _head = Path()
    ..addOval(Rect.fromCircle(center: const Offset(82, 46), radius: 23));
  static final Path _ear = Path()
    ..addOval(Rect.fromCenter(center: const Offset(0, 0), width: 30, height: 13));
  static final Path _innerEarPath = Path()
    ..addOval(Rect.fromCenter(center: const Offset(-2, 0), width: 17, height: 6));
  static final Path _hornL = Path()
    ..moveTo(72, 28)
    ..quadraticBezierTo(66, 14, 56, 12);
  static final Path _hornR = Path()
    ..moveTo(90, 27)
    ..quadraticBezierTo(94, 13, 104, 9);
  static final Path _beard = Path()
    ..moveTo(78, 66)
    ..quadraticBezierTo(80, 78, 85, 81)
    ..quadraticBezierTo(90, 78, 91, 66)
    ..close();
  static final Path _hatDome = Path()
    ..moveTo(60, 34)
    ..cubicTo(56, 8, 106, 8, 104, 34)
    ..close();
  static final Path _hatBand = Path()
    ..addRRect(
      RRect.fromRectAndRadius(const Rect.fromLTRB(59, 29, 105, 37), const Radius.circular(4)),
    );
  static final Path _hatVisor = Path()
    ..moveTo(90, 36)
    ..quadraticBezierTo(108, 34, 114, 39)
    ..quadraticBezierTo(104, 43, 90, 40)
    ..close();
  static final Path _bag = Path()
    ..addRRect(
      RRect.fromRectAndRadius(const Rect.fromLTRB(36, 68, 62, 88), const Radius.circular(5)),
    );
  static final Path _bagFlap = Path()
    ..moveTo(36, 72)
    ..lineTo(36, 70)
    ..quadraticBezierTo(36, 68, 41, 68)
    ..lineTo(57, 68)
    ..quadraticBezierTo(62, 68, 62, 70)
    ..lineTo(62, 76)
    ..lineTo(49, 80)
    ..lineTo(36, 76)
    ..close();
  static final Path _strap = Path()
    ..moveTo(40, 69)
    ..quadraticBezierTo(56, 56, 72, 62);
  static final Path _scrollBody = Path()
    ..addRRect(
      RRect.fromRectAndRadius(const Rect.fromLTRB(20, 46, 62, 62), const Radius.circular(8)),
    );

  /// 걸음 한 번(좌우 한 번 기우뚱)의 길이. SPEC 12.2: 약 0.5초 주기
  static const double stepPeriod = 0.5;

  static void paint(
    Canvas canvas, {
    required Offset at,
    required double size,
    required GoatLook look,
    required double t,
    GoatPose pose = GoatPose.walk,
    bool faceLeft = false,
    double phase = 0,
    double highlight = 0,
    double chew = 0,
  }) {
    final time = t + phase;
    final scale = size / _box;
    final w = 2 * math.pi * time / stepPeriod;
    final walking = pose == GoatPose.walk;

    // 뒤뚱: 좌우 기울기 ±7°, 걸음마다 통통 튀기
    final tilt = walking ? 0.12 * math.sin(w) : 0.025 * math.sin(2 * math.pi * time / 2.6);
    final bounce = walking ? -4.5 * math.sin(w).abs() : 0.0;
    final breathe = walking ? 1.0 : 1 + 0.025 * math.sin(2 * math.pi * time / 2.4);
    final legSwing = walking ? 0.45 * math.sin(w) : 0.0;
    final earFlap = walking ? 0.35 * math.sin(w + 1.2) : 0.12 * math.sin(2 * math.pi * time / 3.1);
    // 하품: 쉬고 있을 때 약 11초마다 1.2초(입을 크게 벌리고 눈을 감는다)
    final yc = time % 11.0;
    final yawn = !walking && chew == 0 && yc > 9.8 ? math.sin(math.pi * (yc - 9.8) / 1.2) : 0.0;
    // 깜빡임: 약 3.7초마다 0.13초
    final blink = (time % 3.7) < 0.13 || yawn > 0.3;
    // 오물오물: 초당 약 4번 씹기
    final munch = chew > 0 ? (0.5 + 0.5 * math.sin(2 * math.pi * 4 * time)) * chew : 0.0;

    // 그림자
    _fill.color = const Color(0x2A5A4636);
    canvas.drawOval(
      Rect.fromCenter(center: at, width: size * (0.55 + 0.04 * bounce / 4.5), height: size * 0.11),
      _fill,
    );

    if (walking) _paintDust(canvas, at, size, time, faceLeft);

    canvas.save();
    canvas.translate(at.dx, at.dy);
    canvas.scale(faceLeft ? -scale : scale, scale);
    canvas.translate(0, bounce);
    canvas.rotate(tilt);
    canvas.scale(1, breathe);
    canvas.translate(-_feet.dx, -_feet.dy);

    if (highlight > 0) {
      _fill.color = Color.fromRGBO(255, 224, 138, 0.55 * highlight);
      canvas.drawCircle(const Offset(62, 62), 58, _fill);
    }

    // 먼 다리(살짝 어둡게)
    _drawLeg(canvas, const Offset(38, 88), -legSwing, _shade);
    _drawLeg(canvas, const Offset(66, 88), legSwing, _shade);

    _shape(canvas, _tail, _white);
    _shape(canvas, _body, _white);

    if (!look.scroll) {
      canvas.drawPath(_strap, _stroke..color = _outline);
      _shape(canvas, _bag, look.bag);
      _shape(canvas, _bagFlap, Color.lerp(look.bag, _white, 0.35)!);
      // 가방에 꽂힌 편지
      _fill.color = _paper;
      canvas.drawRect(const Rect.fromLTRB(44, 63, 54, 69), _fill);
      canvas.drawRect(const Rect.fromLTRB(44, 63, 54, 69), _stroke..strokeWidth = 2.4);
      _stroke.strokeWidth = 4.2;
    }

    // 가까운 다리
    _drawLeg(canvas, const Offset(32, 88), legSwing, _white);
    _drawLeg(canvas, const Offset(72, 88), -legSwing, _white);

    // 뿔(외곽선 굵게 + 크림색)
    for (final horn in [_hornL, _hornR]) {
      canvas.drawPath(
        horn,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeCap = StrokeCap.round
          ..strokeWidth = 11
          ..color = _outline,
      );
      canvas.drawPath(
        horn,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeCap = StrokeCap.round
          ..strokeWidth = 5.5
          ..color = _horn,
      );
    }

    // 귀(뒤쪽으로 축 늘어짐, 걸을 때 팔랑)
    canvas.save();
    canvas.translate(66, 40);
    canvas.rotate(-0.5 + earFlap);
    canvas.translate(-12, 0);
    _shape(canvas, _ear, _white);
    _fill.color = _innerEar;
    canvas.drawPath(_innerEarPath, _fill);
    canvas.restore();

    // 롤링 염소: 등에 진 두루마리(귀 위에 얹힌다)
    if (look.scroll) _paintScroll(canvas, look);

    _shape(canvas, _beard, _white);
    _shape(canvas, _head, _white);

    // 얼굴
    _fill.color = _muzzle;
    canvas.drawOval(Rect.fromCenter(center: const Offset(88, 57), width: 26, height: 16), _fill);
    _fill.color = _blush;
    canvas.drawOval(Rect.fromCenter(center: const Offset(73, 54), width: 10, height: 6), _fill);
    canvas.drawOval(Rect.fromCenter(center: const Offset(100, 53), width: 9, height: 6), _fill);
    if (chew > 0) {
      // 볼 빵빵: 볼이 부풀었다 줄었다
      final r = 6.5 + 2.5 * munch;
      _fill.color = _white;
      canvas.drawCircle(Offset(100 + munch, 57), r, _fill);
      canvas.drawCircle(
        Offset(100 + munch, 57),
        r,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2.4
          ..color = _outline,
      );
      _fill.color = _blush;
      canvas.drawOval(Rect.fromCenter(center: Offset(101 + munch, 56), width: 8, height: 5), _fill);
    }
    if (blink) {
      final p = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3
        ..strokeCap = StrokeCap.round
        ..color = _eye;
      canvas.drawLine(const Offset(76, 46), const Offset(83, 46), p);
      canvas.drawLine(const Offset(91, 46), const Offset(98, 46), p);
    } else {
      _fill.color = _eye;
      canvas.drawOval(
        Rect.fromCenter(center: const Offset(79.5, 45), width: 8, height: 10.5),
        _fill,
      );
      canvas.drawOval(
        Rect.fromCenter(center: const Offset(94.5, 45), width: 8, height: 10.5),
        _fill,
      );
      _fill.color = _white;
      canvas.drawCircle(const Offset(81.2, 42.6), 1.9, _fill);
      canvas.drawCircle(const Offset(96.2, 42.6), 1.9, _fill);
    }
    final mouth = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.6
      ..strokeCap = StrokeCap.round
      ..color = _outline;
    if (yawn > 0.05) {
      // 하~암: 동그랗게 벌린 입
      final o = Rect.fromCenter(
        center: const Offset(88, 60),
        width: 6 + 3 * yawn,
        height: 3 + 7 * yawn,
      );
      _fill.color = const Color(0xFF8C4A4A);
      canvas.drawOval(o, _fill);
      canvas.drawOval(o, mouth);
    } else if (chew > 0) {
      // 오물오물: 입이 옆으로 씰룩
      canvas.drawPath(
        Path()
          ..moveTo(84, 59 + munch)
          ..quadraticBezierTo(88, 61.5 - munch, 92, 59 + munch),
        mouth,
      );
    } else {
      canvas.drawPath(
        Path()
          ..moveTo(83, 58)
          ..quadraticBezierTo(86, 62, 88, 58.5)
          ..quadraticBezierTo(90, 62, 93, 58),
        mouth,
      );
    }

    // 우체부 모자
    canvas.save();
    canvas.translate(82, 30);
    canvas.rotate(-0.12);
    canvas.translate(-82, -30);
    _shape(canvas, _hatDome, look.hat);
    _shape(canvas, _hatBand, Color.lerp(look.hat, const Color(0xFF000000), 0.18)!);
    _shape(canvas, _hatVisor, Color.lerp(look.hat, const Color(0xFF000000), 0.18)!);
    _fill.color = const Color(0xFFFFE08A);
    canvas.drawRRect(
      RRect.fromRectAndRadius(const Rect.fromLTRB(76, 16, 88, 25), const Radius.circular(2)),
      _fill,
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(const Rect.fromLTRB(76, 16, 88, 25), const Radius.circular(2)),
      _stroke..strokeWidth = 2.2,
    );
    canvas.drawPath(
      Path()
        ..moveTo(76, 17)
        ..lineTo(82, 21.5)
        ..lineTo(88, 17),
      _stroke,
    );
    _stroke.strokeWidth = 4.2;
    canvas.restore();

    canvas.restore();
  }

  static void _shape(Canvas canvas, Path path, Color fill) {
    _fill.color = fill;
    canvas.drawPath(path, _fill);
    canvas.drawPath(path, _stroke..color = _outline);
  }

  static void _drawLeg(Canvas canvas, Offset hip, double angle, Color color) {
    canvas.save();
    canvas.translate(hip.dx, hip.dy);
    canvas.rotate(angle);
    _fill.color = color;
    canvas.drawPath(_leg, _fill);
    _fill.color = _hoof;
    canvas.drawPath(_hoofPath, _fill);
    canvas.drawPath(_leg, _stroke);
    canvas.restore();
  }

  static void _paintScroll(Canvas canvas, GoatLook look) {
    _shape(canvas, _scrollBody, _paper);
    _fill.color = look.bag;
    // 양 끝 손잡이 + 가운데 리본
    canvas.drawRRect(
      RRect.fromRectAndRadius(const Rect.fromLTRB(16, 44, 25, 64), const Radius.circular(4)),
      _fill,
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(const Rect.fromLTRB(57, 44, 66, 64), const Radius.circular(4)),
      _fill,
    );
    canvas.drawRect(const Rect.fromLTRB(38, 46, 45, 62), Paint()..color = look.hat);
    for (final r in [const Rect.fromLTRB(16, 44, 25, 64), const Rect.fromLTRB(57, 44, 66, 64)]) {
      canvas.drawRRect(RRect.fromRectAndRadius(r, const Radius.circular(4)), _stroke);
    }
    canvas.drawPath(_scrollBody, _stroke);
  }

  /// 걸음마다 발뒤꿈치에서 피어오르는 작은 먼지
  static void _paintDust(Canvas canvas, Offset at, double size, double time, bool faceLeft) {
    final step = (time % (stepPeriod / 2)) / (stepPeriod / 2);
    final back = faceLeft ? 1.0 : -1.0;
    final alpha = (1 - step) * 0.45;
    if (alpha <= 0.02) return;
    _fill.color = Color.fromRGBO(255, 255, 255, alpha);
    final r = size * (0.03 + 0.05 * step);
    canvas.drawCircle(
      at + Offset(back * size * (0.28 + 0.12 * step), -size * 0.04 * step),
      r,
      _fill,
    );
    canvas.drawCircle(
      at + Offset(back * size * (0.18 + 0.1 * step), -size * (0.02 + 0.06 * step)),
      r * 0.7,
      _fill,
    );
  }
}

/// 시 롤링 염소·배달 염소 공통 색 (SPEC 4.2)
abstract final class RollingLooks {
  static const nation = GoatLook(hat: Color(0xFFF2B705), bag: Color(0xFFFFE08A), scroll: true);
  static const province = GoatLook(hat: Color(0xFF3FBF9B), bag: Color(0xFFBDEBD7), scroll: true);
  static const city = GoatLook(hat: Color(0xFFF27BA0), bag: Color(0xFFFFC9D6), scroll: true);
}

/// "#RRGGBB" → Color
Color colorFromHex(String hex) => Color(int.parse('FF${hex.replaceFirst('#', '')}', radix: 16));
