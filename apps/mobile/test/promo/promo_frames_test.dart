@Tags(['promo'])
library;

// 홍보 영상(tools/promo)에 쓰는 염소 프레임: 앱과 같은 GoatPainterKit으로 그린 투명 PNG.
//   cd apps/mobile && flutter test --tags promo  → build/promo/
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:meeil/features/map/goat_painter.dart';
import 'package:meeil/features/safety/goat_eating.dart';

import '../screenshots/screenshot_helper.dart';

Future<void> savePicture(
  WidgetTester tester,
  void Function(Canvas canvas, Size size) paint,
  Size size,
  String path,
) async {
  await tester.runAsync(() async {
    final rec = ui.PictureRecorder();
    paint(Canvas(rec), size);
    final img = await rec.endRecording().toImage(size.width.round(), size.height.round());
    final bytes = await img.toByteData(format: ui.ImageByteFormat.png);
    File(path)
      ..createSync(recursive: true)
      ..writeAsBytesSync(bytes!.buffer.asUint8List());
  });
}

const looks = {
  'red': GoatLook(hat: Color(0xFFE8505B), bag: Color(0xFFF6C177)),
  'blue': GoatLook(hat: Color(0xFF3F8EFC), bag: Color(0xFFFFC9D6)),
  'nation': RollingLooks.nation,
};

void main() {
  testWidgets('염소 걷기·먹기 프레임', (tester) async {
    await tester.runAsync(loadAppFonts);
    // 걷기 한 주기(0.5초)를 30fps로 15장 + 쉬기 30장(깜빡임 포함), 크기 360px
    const s = Size(360, 360);
    for (final MapEntry(key: name, value: look) in looks.entries) {
      for (var i = 0; i < 15; i++) {
        await savePicture(
          tester,
          (c, size) => GoatPainterKit.paint(
            c,
            at: Offset(size.width / 2, size.height * 0.95),
            size: 300,
            look: look,
            t: i / 30,
          ),
          s,
          'build/promo/goat_${name}_walk_${i.toString().padLeft(2, '0')}.png',
        );
      }
    }
    for (var i = 0; i < 60; i++) {
      await savePicture(
        tester,
        (c, size) => GoatPainterKit.paint(
          c,
          at: Offset(size.width / 2, size.height * 0.95),
          size: 300,
          look: looks['red']!,
          t: 3.6 + i / 30, // 깜빡임이 들어가는 구간
          pose: GoatPose.idle,
        ),
        s,
        'build/promo/goat_red_idle_${i.toString().padLeft(2, '0')}.png',
      );
    }
    // 편지 먹기 연출 2.6초 → 30fps 78장
    for (var i = 0; i < 78; i++) {
      await savePicture(
        tester,
        (c, size) => GoatEatingPainter(i / 77, looks['red']!).paint(c, size),
        const Size(640, 400),
        'build/promo/eat_${i.toString().padLeft(2, '0')}.png',
      );
    }
  });
}
