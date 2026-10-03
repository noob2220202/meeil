@Tags(['screenshot'])
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:meeil/app/theme.dart';
import 'package:meeil/features/map/goat_painter.dart';

import 'screenshot_helper.dart';

/// 걷기 한 주기의 여러 순간을 나란히 그려 뒤뚱 모션을 눈으로 확인한다
class _Sheet extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(Offset.zero & size, Paint()..color = Palette.cream);
    const looks = [
      GoatLook(hat: Color(0xFFE8505B), bag: Color(0xFFF6C177)),
      GoatLook(hat: Color(0xFF3D7DD8), bag: Color(0xFFFFE08A)),
      RollingLooks.nation,
      RollingLooks.province,
      RollingLooks.city,
    ];
    // 1행: 큰 염소 걷기 6프레임
    for (var i = 0; i < 6; i++) {
      GoatPainterKit.paint(
        canvas,
        at: Offset(70.0 + (i % 3) * 130, 130.0 + (i ~/ 3) * 130),
        size: 110,
        look: looks[0],
        t: 1 + i * GoatPainterKit.stepPeriod / 6,
      );
    }
    // 2행: 색 변주 + 왼쪽 보기 + 쉬기
    for (var i = 0; i < looks.length; i++) {
      GoatPainterKit.paint(
        canvas,
        at: Offset(70.0 + (i % 3) * 130, 400.0 + (i ~/ 3) * 120),
        size: 95,
        look: looks[i],
        t: 1.1,
        pose: i.isEven ? GoatPose.walk : GoatPose.idle,
        faceLeft: i == 1,
      );
    }
    // 3행: 지도 크기(40px) 실제 비율
    for (var i = 0; i < 12; i++) {
      GoatPainterKit.paint(
        canvas,
        at: Offset(30.0 + (i % 6) * 66, 680.0 + (i ~/ 6) * 70),
        size: 44,
        look: looks[i % looks.length],
        t: 1 + i * 0.07,
      );
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

void main() {
  testWidgets('염소 스프라이트', (tester) async {
    await captureScreen(
      tester,
      Directionality(
        textDirection: TextDirection.ltr,
        child: CustomPaint(painter: _Sheet(), size: Size.infinite),
      ),
      'm2_goats',
    );
  });
}
