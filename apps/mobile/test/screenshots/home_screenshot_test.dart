@Tags(['screenshot'])
library;

import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:meeil/app/app.dart';
import 'package:meeil/data/regions.dart';

import 'screenshot_helper.dart';

void main() {
  testWidgets('홈(M0) 스크린샷', (tester) async {
    await tester.runAsync(loadAppFonts);
    final data = RegionData.parse(File(regionAssetPath).readAsStringSync());
    await captureScreen(
      tester,
      ProviderScope(
        overrides: [regionDataProvider.overrideWith((ref) async => data)],
        child: const MeeilApp(),
      ),
      'm0_home',
    );
  });
}
