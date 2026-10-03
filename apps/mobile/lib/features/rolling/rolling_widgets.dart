import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../app/theme.dart';
import '../letters/letter_paper.dart';
import 'rolling_models.dart';

/// 두루마리 위·아래 나무 막대
class ScrollRoller extends StatelessWidget {
  const ScrollRoller({super.key, this.height = 22});

  final double height;

  @override
  Widget build(BuildContext context) => SizedBox(
    height: height,
    width: double.infinity,
    child: CustomPaint(painter: _RollerPainter()),
  );
}

class _RollerPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final h = size.height;
    final knob = h * 0.9;
    final rod = RRect.fromRectAndRadius(
      Rect.fromLTWH(knob * 0.6, h * 0.12, size.width - knob * 1.2, h * 0.76),
      Radius.circular(h),
    );
    final wood = Paint()
      ..shader = const LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [Color(0xFFE9B97E), Color(0xFFC98E52), Color(0xFFB07843)],
      ).createShader(rod.outerRect);
    final line = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2
      ..color = Palette.outline;
    canvas.drawRRect(rod, wood);
    canvas.drawRRect(rod, line);
    // 하이라이트
    canvas.drawLine(
      Offset(knob * 1.2, h * 0.32),
      Offset(size.width - knob * 1.2, h * 0.32),
      Paint()
        ..color = const Color(0x66FFFFFF)
        ..strokeWidth = 2
        ..strokeCap = StrokeCap.round,
    );
    for (final cx in [knob / 2, size.width - knob / 2]) {
      final c = Offset(cx, h / 2);
      canvas.drawCircle(c, knob / 2, Paint()..color = const Color(0xFFE08A5C));
      canvas.drawCircle(c, knob / 2, line);
      canvas.drawCircle(
        c.translate(-knob * 0.12, -knob * 0.12),
        knob * 0.12,
        Paint()..color = const Color(0x88FFFFFF),
      );
    }
  }

  @override
  bool shouldRepaint(_RollerPainter old) => false;
}

const _noteColors = [
  Color(0xFFFFF4C2),
  Color(0xFFE3F6EC),
  Color(0xFFFFE6EC),
  Color(0xFFE6F2FF),
  Color(0xFFF1E9FF),
];

int _hash(String s) {
  var h = 0;
  for (final c in s.codeUnits) {
    h = (h * 31 + c) & 0x7fffffff;
  }
  return h;
}

/// 두루마리에 붙은 한마디 쪽지. 기울기·색은 id로 정해져 매번 같다.
class NoteCard extends StatelessWidget {
  const NoteCard({super.key, required this.entry, this.width = 160});

  final RollingEntry entry;
  final double width;

  @override
  Widget build(BuildContext context) {
    final h = _hash(entry.id);
    final color = _noteColors[h % _noteColors.length];
    final angle = ((h >> 4) % 9 - 4) * 0.55 * math.pi / 180;
    final author = entry.author.title == null
        ? entry.author.nickname
        : '${entry.author.nickname} · ${entry.author.title}';
    final body = entry.eaten
        ? Text(
            '냠냠… 염소가 먹어 버린 한마디예요',
            style: TextStyle(fontSize: 13, color: Palette.textBrown.withValues(alpha: 0.6)),
          )
        : Text(
            entry.body ?? '',
            style: const TextStyle(
              fontFamily: Fonts.handwriting,
              fontFamilyFallback: Fonts.fallback,
              fontSize: 19,
              height: 1.25,
              color: Palette.textBrown,
            ),
          );
    return Semantics(
      label: entry.eaten ? '$author의 한마디, 염소가 먹었어요' : '$author: ${entry.body}',
      excludeSemantics: true,
      child: Transform.rotate(
        angle: angle,
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            Container(
              width: width,
              padding: const EdgeInsets.fromLTRB(12, 14, 12, 10),
              decoration: BoxDecoration(
                color: color,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: entry.mine ? const Color(0xFFE0A100) : Palette.outline,
                  width: entry.mine ? 2.5 : 1.5,
                ),
                boxShadow: const [BoxShadow(color: Color(0x225A4636), offset: Offset(0, 3))],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  body,
                  const SizedBox(height: 8),
                  Align(
                    alignment: Alignment.centerRight,
                    child: Text(
                      '— $author',
                      textAlign: TextAlign.right,
                      style: const TextStyle(fontSize: 12, color: Palette.textBrown),
                    ),
                  ),
                ],
              ),
            ),
            for (final s in entry.stickers)
              Positioned(
                left: s.x * (width - 30) - 4,
                top: s.y * 40 - 12,
                child: IgnorePointer(child: StickerImage(s.id, size: 34)),
              ),
            if (entry.mine)
              Positioned(
                top: -9,
                left: width / 2 - 26,
                child: Transform.rotate(
                  angle: -0.06,
                  child: Container(
                    width: 52,
                    height: 18,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: const Color(0xCCFFE08A),
                      borderRadius: BorderRadius.circular(3),
                    ),
                    child: const Text(
                      '내 글',
                      style: TextStyle(
                        fontFamily: Fonts.title,
                        fontFamilyFallback: Fonts.fallback,
                        fontSize: 11,
                        color: Palette.textBrown,
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// 상태 알약(카드 아래 "한마디 3개" 등)
class Pill extends StatelessWidget {
  const Pill(this.text, {super.key, this.color = Colors.white, this.icon});

  final String text;
  final Color color;
  final IconData? icon;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
    decoration: BoxDecoration(
      color: color,
      borderRadius: BorderRadius.circular(99),
      border: Border.all(color: Palette.outline, width: 1.5),
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (icon != null) ...[
          Icon(icon, size: 14, color: Palette.textBrown),
          const SizedBox(width: 3),
        ],
        Flexible(
          child: Text(
            text,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 12.5, color: Palette.textBrown),
          ),
        ),
      ],
    ),
  );
}
