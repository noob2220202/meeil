import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../../app/theme.dart';
import 'letter_models.dart';

/// 편지지 3종 (SPEC 7.2): 크림 / 줄노트 / 하늘 구름
class StationeryStyle {
  const StationeryStyle(this.id, this.name, this.paper, this.ink, {this.lined = false});

  final String id;
  final String name;
  final Color paper;
  final Color ink;
  final bool lined;

  static const cream = StationeryStyle('cream', '크림', Color(0xFFFFF8EC), Palette.textBrown);
  static const lined_ = StationeryStyle(
    'lined',
    '줄노트',
    Color(0xFFFFFDF6),
    Color(0xFF4A5A7A),
    lined: true,
  );
  static const skyCloud = StationeryStyle(
    'sky-cloud',
    '하늘 구름',
    Color(0xFFE6F5FF),
    Color(0xFF3F5E86),
  );

  static const all = [cream, lined_, skyCloud];

  static StationeryStyle of(String id) => all.firstWhere((s) => s.id == id, orElse: () => cream);
}

/// 편지 손글씨 줄 높이(줄노트 선과 맞춘다)
const letterFontSize = 21.0;
const letterLineHeight = 30.0;

TextStyle letterTextStyle(StationeryStyle s) => TextStyle(
  fontFamily: Fonts.handwriting,
  fontFamilyFallback: Fonts.fallback,
  fontSize: letterFontSize,
  height: letterLineHeight / letterFontSize,
  color: s.ink,
);

/// 편지지 한 장. [child]는 본문 영역, [stickers]는 위에 붙는다.
class LetterPaper extends StatelessWidget {
  const LetterPaper({
    super.key,
    required this.stationeryId,
    required this.child,
    this.stickers = const [],
    this.stickerSize = 56,
    this.onStickerMoved,
    this.onStickerRemoved,
  });

  final String stationeryId;
  final Widget child;
  final List<PlacedSticker> stickers;
  final double stickerSize;

  /// 쓰기 화면에서만: 스티커를 끌어 옮기기 / 길게 눌러 떼기
  final void Function(int index, double x, double y)? onStickerMoved;
  final void Function(int index)? onStickerRemoved;

  @override
  Widget build(BuildContext context) {
    final style = StationeryStyle.of(stationeryId);
    return LayoutBuilder(
      builder: (context, box) {
        final size = box.biggest;
        return DecoratedBox(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(18),
            boxShadow: const [BoxShadow(color: Color(0x335A4636), offset: Offset(0, 4))],
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(18),
            child: CustomPaint(
              painter: _PaperPainter(style),
              foregroundPainter: _PaperBorder(),
              child: Stack(
                children: [
                  Positioned.fill(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(28, 22, 22, 22),
                      child: child,
                    ),
                  ),
                  for (var i = 0; i < stickers.length; i++)
                    _StickerOnPaper(
                      key: ValueKey('sticker-$i-${stickers[i].id}'),
                      sticker: stickers[i],
                      paper: size,
                      size: stickerSize,
                      onMoved: onStickerMoved == null ? null : (x, y) => onStickerMoved!(i, x, y),
                      onRemove: onStickerRemoved == null ? null : () => onStickerRemoved!(i),
                    ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

class _StickerOnPaper extends StatelessWidget {
  const _StickerOnPaper({
    super.key,
    required this.sticker,
    required this.paper,
    required this.size,
    this.onMoved,
    this.onRemove,
  });

  final PlacedSticker sticker;
  final Size paper;
  final double size;
  final void Function(double x, double y)? onMoved;
  final VoidCallback? onRemove;

  @override
  Widget build(BuildContext context) {
    final left = sticker.x * (paper.width - size);
    final top = sticker.y * (paper.height - size);
    // 스티커마다 살짝 기울여 붙인 느낌
    final tilt = ((sticker.id.hashCode % 7) - 3) * 0.04;
    final image = Transform.rotate(
      angle: tilt,
      child: StickerImage(sticker.id, size: size),
    );
    return Positioned(
      left: left,
      top: top,
      child: onMoved == null
          ? IgnorePointer(child: image)
          : Semantics(
              label: '스티커 ${stickerLabel(sticker.id)}. 끌어서 옮기고 길게 눌러 떼기',
              child: GestureDetector(
                onPanUpdate: (d) => onMoved!(
                  (left + d.delta.dx) / math.max(1, paper.width - size),
                  (top + d.delta.dy) / math.max(1, paper.height - size),
                ),
                onLongPress: onRemove,
                child: image,
              ),
            ),
    );
  }
}

class StickerImage extends StatelessWidget {
  const StickerImage(this.id, {super.key, this.size = 48});

  final String id;
  final double size;

  @override
  Widget build(BuildContext context) =>
      SvgPicture.asset('assets/stickers/$id.svg', width: size, height: size);
}

String stickerLabel(String id) =>
    const {
      'heart': '하트',
      'star': '별',
      'flower': '꽃',
      'clover': '클로버',
      'cloud': '구름',
      'sun': '해',
      'moon': '달',
      'note': '음표',
      'letter': '편지',
      'gift': '선물',
      'ribbon': '리본',
      'rainbow': '무지개',
      'cherry': '체리',
      'leaf': '나뭇잎',
      'goat-smile': '웃는 염소',
      'goat-love': '반한 염소',
      'goat-sleep': '조는 염소',
      'goat-wow': '놀란 염소',
      'goat-laugh': '깔깔 염소',
      'goat-tear': '눈물 염소',
    }[id] ??
    id;

class _PaperPainter extends CustomPainter {
  _PaperPainter(this.style);
  final StationeryStyle style;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(Offset.zero & size, Paint()..color = style.paper);
    switch (style.id) {
      case 'lined':
        final line = Paint()
          ..color = const Color(0xFFBFDDF5)
          ..strokeWidth = 1.4;
        for (var y = 22 + letterLineHeight; y < size.height - 10; y += letterLineHeight) {
          canvas.drawLine(Offset(14, y + 2), Offset(size.width - 14, y + 2), line);
        }
        canvas.drawLine(
          const Offset(22, 0),
          Offset(22, size.height),
          Paint()
            ..color = const Color(0xFFFFB3C4)
            ..strokeWidth = 1.6,
        );
      case 'sky-cloud':
        _cloud(canvas, Offset(size.width - 54, 30), 1.0);
        _cloud(canvas, Offset(40, size.height - 34), 0.8);
        _cloud(canvas, Offset(size.width * 0.55, size.height - 70), 0.55);
      default:
        // 크림: 모서리에 작은 점무늬
        final dot = Paint()..color = const Color(0x22F28DB2);
        for (var i = 0; i < 6; i++) {
          canvas.drawCircle(Offset(size.width - 18 - i * 9.0, 14), 2.4, dot);
          canvas.drawCircle(Offset(18 + i * 9.0, size.height - 14), 2.4, dot);
        }
    }
  }

  void _cloud(Canvas canvas, Offset c, double s) {
    final p = Paint()..color = const Color(0xFFFFFFFF);
    canvas.drawCircle(c + Offset(-16 * s, 4 * s), 12 * s, p);
    canvas.drawCircle(c + Offset(0, -4 * s), 16 * s, p);
    canvas.drawCircle(c + Offset(17 * s, 4 * s), 11 * s, p);
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTRB(c.dx - 26 * s, c.dy + 2 * s, c.dx + 26 * s, c.dy + 14 * s),
        Radius.circular(8 * s),
      ),
      p,
    );
  }

  @override
  bool shouldRepaint(_PaperPainter old) => old.style.id != style.id;
}

class _PaperBorder extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRRect(
      RRect.fromRectAndRadius((Offset.zero & size).deflate(1.25), const Radius.circular(17)),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.5
        ..color = Palette.outline,
    );
  }

  @override
  bool shouldRepaint(_PaperBorder old) => false;
}
