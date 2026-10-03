import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../app/theme.dart';
import '../goats/schedule.dart';
import '../map/goat_painter.dart';
import 'letter_models.dart';

/// 맡기기 연출: 봉투가 날아와 염소 가방에 쏙 → 염소가 콩 뛰고 → 뒤뚱뒤뚱 떠난다.
Future<void> showHandoff(
  BuildContext context, {
  required GoatLook look,
  required String goatName,
  required Letter letter,
}) {
  return showGeneralDialog<void>(
    context: context,
    barrierDismissible: true,
    barrierLabel: '닫기',
    barrierColor: const Color(0xCCFFF8EC),
    transitionDuration: const Duration(milliseconds: 200),
    pageBuilder: (context, _, _) => _Handoff(look: look, goatName: goatName, letter: letter),
  );
}

class _Handoff extends StatefulWidget {
  const _Handoff({required this.look, required this.goatName, required this.letter});

  final GoatLook look;
  final String goatName;
  final Letter letter;

  @override
  State<_Handoff> createState() => _HandoffState();
}

class _HandoffState extends State<_Handoff> with SingleTickerProviderStateMixin {
  late final _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 2600));

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (MediaQuery.disableAnimationsOf(context)) {
      _c.value = 0.5;
    } else if (!_c.isAnimating && _c.value == 0) {
      _c.forward();
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final eta = widget.letter.etaAt;
    final remaining = eta?.difference(widget.letter.handedAt);
    return GestureDetector(
      onTap: () => Navigator.pop(context),
      child: Material(
        color: Colors.transparent,
        child: SafeArea(
          child: Column(
            children: [
              const Spacer(),
              SizedBox(
                height: 220,
                child: AnimatedBuilder(
                  animation: _c,
                  builder: (context, _) => CustomPaint(
                    size: Size.infinite,
                    painter: _HandoffPainter(_c.value, widget.look),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Text(
                '${widget.goatName}가 편지를 들고 출발했어요!',
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontFamily: Fonts.title,
                  fontFamilyFallback: Fonts.fallback,
                  fontSize: 22,
                ),
              ),
              const SizedBox(height: 8),
              if (eta != null && remaining != null)
                Text(
                  '${widget.letter.express ? '특급 배달 · ' : ''}약 ${formatRemaining(remaining)} 뒤 ${formatClock(eta)}쯤 도착해요',
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontSize: 16),
                ),
              const SizedBox(height: 4),
              const Text('보낸 편지함에서 염소의 여정을 볼 수 있어요', style: TextStyle(fontSize: 13)),
              const Spacer(),
              const Padding(
                padding: EdgeInsets.only(bottom: 24),
                child: Text('화면을 누르면 닫혀요', style: TextStyle(fontSize: 12)),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _HandoffPainter extends CustomPainter {
  _HandoffPainter(this.p, this.look);

  final double p;
  final GoatLook look;

  @override
  void paint(Canvas canvas, Size size) {
    final ground = size.height * 0.9;
    final cx = size.width / 2;
    // 0.0~0.3 봉투 날아옴, 0.3~0.45 콩 뛰기, 0.45~1.0 오른쪽으로 걸어 나감
    final hop = p > 0.3 && p < 0.45 ? -26 * math.sin((p - 0.3) / 0.15 * math.pi) : 0.0;
    final walkT = ((p - 0.45) / 0.55).clamp(0.0, 1.0);
    final x = cx + Curves.easeIn.transform(walkT) * (size.width * 0.75);
    final t = p * 2.6;
    GoatPainterKit.paint(
      canvas,
      at: Offset(x, ground + hop),
      size: 150,
      look: look,
      t: t,
      pose: walkT > 0 ? GoatPose.walk : GoatPose.idle,
    );
    if (p < 0.32) {
      // 봉투: 왼쪽 아래에서 포물선으로 가방까지
      final f = Curves.easeOut.transform((p / 0.3).clamp(0.0, 1.0));
      final start = Offset(cx - 150, ground - 10);
      final end = Offset(cx - 18, ground - 70);
      final pos = Offset.lerp(start, end, f)! + Offset(0, -80 * math.sin(f * math.pi));
      _envelope(canvas, pos, 1 - 0.4 * f, f * 6);
    }
  }

  void _envelope(Canvas canvas, Offset c, double s, double spin) {
    canvas.save();
    canvas.translate(c.dx, c.dy);
    canvas.rotate(spin * 0.2);
    canvas.scale(s);
    final r = RRect.fromRectAndRadius(
      Rect.fromCenter(center: Offset.zero, width: 52, height: 36),
      const Radius.circular(6),
    );
    canvas.drawRRect(r, Paint()..color = const Color(0xFFFFF8EC));
    final stroke = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3
      ..strokeJoin = StrokeJoin.round
      ..color = Palette.outline;
    canvas.drawRRect(r, stroke);
    canvas.drawPath(
      Path()
        ..moveTo(-24, -16)
        ..lineTo(0, 2)
        ..lineTo(24, -16),
      stroke,
    );
    canvas.drawCircle(const Offset(0, 4), 5, Paint()..color = const Color(0xFFFF8FAB));
    canvas.restore();
  }

  @override
  bool shouldRepaint(_HandoffPainter old) => old.p != p;
}
