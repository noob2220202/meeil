import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../app/theme.dart';
import '../../core/sound.dart';
import '../map/goat_painter.dart';

/// 염소가 편지를 냠냠 먹어버리는 연출 (SPEC 9.3). 한 번 재생하고 마지막 장면에서 멈춘다.
/// 동작 줄이기 설정이면 바로 마지막 장면.
class GoatEatingScene extends StatefulWidget {
  const GoatEatingScene({super.key, required this.look, this.height = 150, this.frozenAt});

  final GoatLook look;
  final double height;

  /// 스크린샷·테스트용: 이 진행도(0~1)에서 멈춘다
  @visibleForTesting
  final double? frozenAt;

  @override
  State<GoatEatingScene> createState() => _GoatEatingSceneState();
}

class _GoatEatingSceneState extends State<GoatEatingScene> with SingleTickerProviderStateMixin {
  late final _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 2600));
  bool _started = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_started) return;
    _started = true;
    if (widget.frozenAt != null) {
      _c.value = widget.frozenAt!;
    } else if (MediaQuery.disableAnimationsOf(context)) {
      _c.value = 1;
    } else {
      _c.forward();
      playSfxIn(context, Sfx.chomp);
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Semantics(
    label: '염소가 편지를 냠냠 먹어버렸어요',
    image: true,
    child: SizedBox(
      height: widget.height,
      width: widget.height * 1.6,
      child: AnimatedBuilder(
        animation: _c,
        builder: (context, _) => CustomPaint(painter: GoatEatingPainter(_c.value, widget.look)),
      ),
    ),
  );
}

class GoatEatingPainter extends CustomPainter {
  GoatEatingPainter(this.p, this.look);

  /// 진행도 0~1: 0~0.2 봉투 발견, 0.2~0.75 네 입에 걸쳐 먹기, 0.75~1 "냠냠" 만족
  final double p;
  final GoatLook look;

  static const _bites = 4;

  @override
  void paint(Canvas canvas, Size size) {
    final goatSize = size.height * 0.92;
    final scale = goatSize / 120;
    final feet = Offset(size.width * 0.36, size.height * 0.97);
    // 씹을 때 고개가 까딱까딱
    final eating = p > 0.2 && p < 0.8;
    final chomp = eating ? math.sin(p * math.pi * 22).abs() * 3 * scale : 0.0;
    GoatPainterKit.paint(
      canvas,
      at: feet + Offset(0, chomp),
      size: goatSize,
      look: look,
      t: p * 2.6,
      pose: GoatPose.idle,
      // 먹는 동안 볼 빵빵 + 오물오물(SPEC 12.2)
      chew: eating ? 1 : 0,
    );
    final mouth = feet + Offset((88 - 60) * scale, (60 - 104) * scale + chomp);

    // 봉투: 바닥에서 입으로 들려 올라가며 한 입씩 줄어든다
    final lift = Curves.easeOut.transform(((p - 0.08) / 0.15).clamp(0.0, 1.0));
    final ground = Offset(size.width * 0.78, size.height * 0.8);
    final held = mouth + Offset(22 * scale, 6 * scale);
    final at = Offset.lerp(ground, held, lift)!;
    final eaten = ((p - 0.22) / 0.53).clamp(0.0, 1.0);
    final bitesTaken = (eaten * _bites).floor();
    if (eaten < 1) _envelope(canvas, at, scale, bitesTaken);

    // 부스러기
    if (p > 0.22) {
      final crumb = Paint()..color = const Color(0xFFE9DCC8);
      final rnd = math.Random(7);
      final n = (bitesTaken + 1) * 4;
      for (var i = 0; i < n; i++) {
        final born = 0.22 + (i / n) * 0.55;
        final age = ((p - born) / 0.35).clamp(0.0, 1.0);
        if (age <= 0 || age >= 1) continue;
        final dx = (rnd.nextDouble() - 0.3) * 30 * scale;
        final fall = age * (size.height * 0.85 - held.dy);
        canvas.drawCircle(
          held + Offset(dx, 8 * scale + fall),
          (1.6 + rnd.nextDouble() * 1.8) * scale,
          crumb,
        );
      }
    }

    // 냠냠 말풍선
    final say = ((p - 0.3) / 0.1).clamp(0.0, 1.0);
    if (say > 0) {
      final word = p < 0.82 ? '냠냠' : '꿀꺽!';
      final tp = TextPainter(
        text: TextSpan(
          text: word,
          style: TextStyle(
            fontFamily: Fonts.title,
            fontFamilyFallback: Fonts.fallback,
            fontSize: 15 * scale * 1.1,
            color: Palette.textBrown.withValues(alpha: say),
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      final pos = mouth + Offset(30 * scale, -46 * scale);
      final bubble = RRect.fromRectAndRadius(
        Rect.fromCenter(center: pos, width: tp.width + 18 * scale, height: tp.height + 10 * scale),
        Radius.circular(12 * scale),
      );
      canvas.drawRRect(bubble, Paint()..color = Colors.white.withValues(alpha: say));
      canvas.drawRRect(
        bubble,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2
          ..color = Palette.outline.withValues(alpha: say),
      );
      tp.paint(canvas, pos - Offset(tp.width / 2, tp.height / 2));
    }

    // 다 먹고 만족: 볼 옆 반짝이
    if (p > 0.8) {
      final s = ((p - 0.8) / 0.2).clamp(0.0, 1.0);
      final star = Paint()..color = const Color(0xFFFFE08A);
      for (final (dx, dy) in [(-26.0, -20.0), (14.0, -30.0)]) {
        _sparkle(canvas, mouth + Offset(dx * scale, dy * scale), 5 * scale * s, star);
      }
    }
  }

  /// 봉투 한 장. [bites]만큼 오른쪽부터 동그랗게 베어 문 자국.
  void _envelope(Canvas canvas, Offset c, double scale, int bites) {
    final w = 46 * scale;
    final h = 32 * scale;
    final rect = Rect.fromCenter(center: c, width: w, height: h);
    canvas.saveLayer(rect.inflate(6 * scale), Paint());
    final body = RRect.fromRectAndRadius(rect, Radius.circular(5 * scale));
    canvas.drawRRect(body, Paint()..color = Colors.white);
    final stroke = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.4
      ..strokeJoin = StrokeJoin.round
      ..color = Palette.outline;
    canvas.drawRRect(body, stroke);
    canvas.drawPath(
      Path()
        ..moveTo(rect.left + 2, rect.top + 2)
        ..lineTo(c.dx, c.dy + 2 * scale)
        ..lineTo(rect.right - 2, rect.top + 2),
      stroke,
    );
    canvas.drawCircle(
      c + Offset(0, 4 * scale),
      4.5 * scale,
      Paint()..color = const Color(0xFFFF8FAB),
    );
    // 베어 문 자국: 왼쪽(입 쪽)부터
    final clear = Paint()..blendMode = BlendMode.clear;
    // 한 입마다 왼쪽 끝을 크게 한 번, 위·아래 모서리를 조금 더(톱니 같은 이빨 자국)
    for (var i = 0; i < bites; i++) {
      final x = rect.left + i * w / _bites;
      canvas.drawCircle(Offset(x, c.dy), h * 0.42, clear);
      canvas.drawCircle(Offset(x + w * 0.1, rect.top + h * 0.12), h * 0.2, clear);
      canvas.drawCircle(Offset(x + w * 0.1, rect.bottom - h * 0.12), h * 0.2, clear);
    }
    canvas.restore();
  }

  void _sparkle(Canvas canvas, Offset c, double r, Paint paint) {
    if (r <= 0) return;
    final path = Path();
    for (var i = 0; i < 8; i++) {
      final a = i * math.pi / 4;
      final rr = i.isEven ? r : r * 0.35;
      final pt = c + Offset(math.cos(a) * rr, math.sin(a) * rr);
      i == 0 ? path.moveTo(pt.dx, pt.dy) : path.lineTo(pt.dx, pt.dy);
    }
    canvas.drawPath(path..close(), paint);
  }

  @override
  bool shouldRepaint(GoatEatingPainter old) => old.p != p || old.look != look;
}
