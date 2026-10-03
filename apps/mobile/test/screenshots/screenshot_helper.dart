import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

/// 실제 번들 폰트를 테스트 환경에 로드한다(기본 테스트 폰트는 네모 글꼴).
Future<void> loadAppFonts() async {
  const fonts = {
    'Jua': ['assets/fonts/Jua-Regular.ttf'],
    'GowunDodum': ['assets/fonts/GowunDodum-Regular.ttf'],
    'Gaegu': ['assets/fonts/Gaegu-Regular.ttf', 'assets/fonts/Gaegu-Bold.ttf'],
  };
  // 머티리얼 아이콘(테스트 기본 환경에서는 네모로 그려진다)
  final flutterRoot = Platform.environment['FLUTTER_ROOT'] ?? '/opt/sdk/flutter';
  final icons = File('$flutterRoot/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf');
  if (icons.existsSync()) {
    await (FontLoader(
      'MaterialIcons',
    )..addFont(Future.value(ByteData.sublistView(icons.readAsBytesSync())))).load();
  }
  for (final entry in fonts.entries) {
    final loader = FontLoader(entry.key);
    for (final path in entry.value) {
      loader.addFont(Future.value(ByteData.sublistView(File(path).readAsBytesSync())));
    }
    await loader.load();
  }
}

/// Galaxy S 계열 논리 해상도(412x915, DPR 2.625)로 위젯을 그려 `build/screenshots/<name>.png`로 저장한다.
Future<void> captureScreen(
  WidgetTester tester,
  Widget app,
  String name, {
  Future<void> Function(WidgetTester tester)? beforeCapture,
}) async {
  tester.view.physicalSize = const Size(1080, 2400);
  tester.view.devicePixelRatio = 2.625;
  addTearDown(tester.view.reset);
  // 반복 애니메이션을 멈춰 정지 프레임을 찍는다
  tester.platformDispatcher.accessibilityFeaturesTestValue = const FakeAccessibilityFeatures(
    disableAnimations: true,
  );
  addTearDown(tester.platformDispatcher.clearAccessibilityFeaturesTestValue);
  final key = GlobalKey();
  await tester.pumpWidget(RepaintBoundary(key: key, child: app));
  await tester.pumpAndSettle();
  if (beforeCapture != null) {
    await beforeCapture(tester);
    await tester.pumpAndSettle();
  }
  await tester.runAsync(() async {
    final boundary = key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
    final image = await boundary.toImage(pixelRatio: 2.625);
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    final file = File('build/screenshots/$name.png')..createSync(recursive: true);
    file.writeAsBytesSync(bytes!.buffer.asUint8List());
  });
}
