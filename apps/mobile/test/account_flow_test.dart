import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:meeil/app/app.dart';
import 'package:meeil/core/token_store.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/fakes.dart';

void main() {
  testWidgets('설정 → 탈퇴: 닉네임을 맞게 적어야 버튼이 켜지고, 탈퇴 후 로그인 화면', (tester) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 2.625;
    addTearDown(tester.view.reset);
    tester.platformDispatcher.accessibilityFeaturesTestValue = const FakeAccessibilityFeatures(
      disableAnimations: true,
    );
    addTearDown(tester.platformDispatcher.clearAccessibilityFeaturesTestValue);
    SharedPreferences.setMockInitialValues({
      'flags.introSeen': true,
      'flags.permissionsIntroDone': true,
    });
    final backend = FakeBackend();
    final store = MemoryTokenStore()..tokens = backend.signedUp('떠날염소');
    final overrides = await appOverrides(backend: backend, store: store);
    await tester.pumpWidget(ProviderScope(overrides: overrides, child: const MeeilApp()));
    await tester.pumpAndSettle();

    await tester.tap(find.text('내 정보'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('menu-settings')));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(find.byKey(const ValueKey('delete-account')), 300);
    await tester.tap(find.byKey(const ValueKey('delete-account')));
    await tester.pumpAndSettle();
    expect(find.text('정말 탈퇴할까요?'), findsOneWidget);

    final confirm = find.byKey(const ValueKey('delete-confirm'));
    expect(tester.widget<TextButton>(confirm).onPressed, isNull);
    await tester.enterText(find.byKey(const ValueKey('delete-confirm-nickname')), '떠날');
    await tester.pump();
    expect(tester.widget<TextButton>(confirm).onPressed, isNull);
    await tester.enterText(find.byKey(const ValueKey('delete-confirm-nickname')), '떠날염소');
    await tester.pump();
    await tester.tap(confirm);
    await tester.pumpAndSettle();

    expect(backend.deleted, hasLength(1));
    expect(store.tokens, isNull);
    expect(find.text('카카오로 시작하기'), findsOneWidget);
    expect(find.textContaining('탈퇴했어요'), findsOneWidget);
  });
}
