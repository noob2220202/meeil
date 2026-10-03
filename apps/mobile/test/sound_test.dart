import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:meeil/app/theme.dart';
import 'package:meeil/core/sound.dart';
import 'package:meeil/core/token_store.dart';
import 'package:meeil/features/letters/letter_screen.dart';
import 'package:meeil/features/map/goat_painter.dart';
import 'package:meeil/features/safety/goat_eating.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/fakes.dart';

Future<ProviderContainer> pumpWith(
  WidgetTester tester,
  Widget child,
  FakeSoundPlayer sounds,
) async {
  final overrides = await appOverrides(
    backend: FakeBackend(),
    store: MemoryTokenStore(),
    sounds: sounds,
  );
  final container = ProviderContainer(overrides: overrides);
  addTearDown(container.dispose);
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        theme: buildTheme(),
        home: Scaffold(body: child),
      ),
    ),
  );
  return container;
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('효과음 파일 6종이 번들에 있고 pubspec에 등록돼 있다', () {
    for (final s in Sfx.values) {
      final f = File('assets/sounds/${s.file}.wav');
      expect(f.existsSync(), isTrue, reason: s.file);
      expect(f.lengthSync(), lessThan(64 * 1024));
      expect(String.fromCharCodes(f.readAsBytesSync().take(4)), 'RIFF');
    }
    expect(File('pubspec.yaml').readAsStringSync(), contains('- assets/sounds/'));
  });

  testWidgets('염소가 먹는 연출은 냠냠 소리, 끄면 조용', (tester) async {
    final sounds = FakeSoundPlayer();
    const look = GoatLook(hat: Colors.red, bag: Colors.orange);
    final c = await pumpWith(tester, const GoatEatingScene(look: look), sounds);
    await tester.pump(const Duration(seconds: 3));
    expect(sounds.played, [Sfx.chomp]);

    await c.read(soundEnabledProvider.notifier).set(false);
    await tester.pumpWidget(Container());
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: c,
        child: const MaterialApp(
          home: Scaffold(body: GoatEatingScene(look: look)),
        ),
      ),
    );
    await tester.pump(const Duration(seconds: 3));
    expect(sounds.played, [Sfx.chomp]);
    // 설정은 기기에 남는다
    expect((await SharedPreferences.getInstance()).getBool('sound.enabled'), isFalse);
  });

  testWidgets('편지 도착: 울음 → 봉투 열리는 소리', (tester) async {
    final sounds = FakeSoundPlayer();
    var done = false;
    await pumpWith(
      tester,
      ArrivalScene(letter: sampleReceived(), onDone: () => done = true),
      sounds,
    );
    await tester.pump(const Duration(milliseconds: 500));
    expect(sounds.played, [Sfx.bleat]);
    await tester.pump(const Duration(milliseconds: 1500));
    await tester.pump(const Duration(milliseconds: 1000));
    expect(sounds.played, [Sfx.bleat, Sfx.letterOpen]);
    expect(done, isTrue);
  });

  testWidgets('동작 줄이기면 연출 없이 소리도 없다', (tester) async {
    tester.platformDispatcher.accessibilityFeaturesTestValue = const FakeAccessibilityFeatures(
      disableAnimations: true,
    );
    addTearDown(tester.platformDispatcher.clearAccessibilityFeaturesTestValue);
    final sounds = FakeSoundPlayer();
    await pumpWith(tester, const GoatEatingScene(look: RollingLooks.city), sounds);
    await tester.pump();
    expect(sounds.played, isEmpty);
  });
}
