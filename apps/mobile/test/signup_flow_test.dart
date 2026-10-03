import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:meeil/app/app.dart';
import 'package:meeil/core/token_store.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/fakes.dart';

Future<void> launch(WidgetTester tester, List<Override> overrides) async {
  // 새 ProviderScope = 앱 재실행
  await tester.pumpWidget(Container());
  await tester.pumpWidget(
    ProviderScope(key: UniqueKey(), overrides: overrides, child: const MeeilApp()),
  );
  await tester.pumpAndSettle();
}

Future<void> tapText(WidgetTester tester, String text) async {
  await tester.tap(find.text(text));
  await tester.pumpAndSettle();
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  // 반복 애니메이션(염소 통통)을 멈춰 pumpAndSettle이 끝나게 한다
  Future<void> reduceMotion(WidgetTester tester) async {
    tester.platformDispatcher.accessibilityFeaturesTestValue = const FakeAccessibilityFeatures(
      disableAnimations: true,
    );
    addTearDown(tester.platformDispatcher.clearAccessibilityFeaturesTestValue);
  }

  testWidgets('가입 → 홈 → 재실행해도 로그인 유지 → 로그아웃', (tester) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 2.625;
    addTearDown(tester.view.reset);

    await reduceMotion(tester);
    final backend = FakeBackend();
    final store = MemoryTokenStore();
    final permissions = FakePermissions();

    await launch(
      tester,
      await appOverrides(backend: backend, store: store, permissions: permissions),
    );

    // 온보딩 3컷
    expect(find.text('건너뛰기'), findsOneWidget);
    await tapText(tester, '다음');
    await tapText(tester, '다음');
    await tapText(tester, '시작하기');

    // 로그인
    expect(find.text('카카오로 시작하기'), findsOneWidget);
    await tapText(tester, '카카오로 시작하기');

    // 1. 약관
    expect(find.textContaining('약관에 동의해 주세요'), findsOneWidget);
    await tapText(tester, '전체 동의');
    await tapText(tester, '동의하고 계속');

    // 2. 생년월일 (기본값 2005-01-01) + 확인 대화상자
    expect(find.text('생일이 언제예요?'), findsOneWidget);
    await tapText(tester, '다음');
    expect(find.textContaining('2005년 1월 1일이 맞나요?'), findsOneWidget);
    await tapText(tester, '맞아요');

    // 3. 닉네임: 중복 → 사용 가능
    expect(find.text('뭐라고 불러 드릴까요?'), findsOneWidget);
    await tester.enterText(find.byType(TextField), '메롱이');
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pumpAndSettle();
    expect(find.text('이미 누군가 쓰고 있는 닉네임이에요.'), findsOneWidget);
    await tester.enterText(find.byType(TextField), '가!');
    await tester.pumpAndSettle();
    expect(find.text('한글, 영문, 숫자만 쓸 수 있어요.'), findsOneWidget);
    await tester.enterText(find.byType(TextField), '뽀얀염소');
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pumpAndSettle();
    expect(find.text('멋진 닉네임이에요!'), findsOneWidget);
    await tapText(tester, '이걸로 할게요');

    // 4. 권한 안내
    expect(find.text('거의 다 왔어요!'), findsOneWidget);
    await tapText(tester, '허용하기');
    expect(permissions.locationRequests, 1);
    expect(permissions.notificationRequests, 1);

    // 홈 = 지도 탭(위치 권한 없음 → 위치 켜기 안내)
    expect(find.text('우리 동네 염소를 기다려 볼까요?'), findsOneWidget);
    await tapText(tester, '내 정보');
    expect(find.text('뽀얀염소님, 어서 와요!'), findsOneWidget);
    expect(find.text('5P'), findsOneWidget);
    expect(store.tokens, isNotNull);

    // 재실행: 같은 저장소 → 바로 홈
    await launch(tester, await appOverrides(backend: backend, store: store));
    expect(find.text('우리 동네 염소를 기다려 볼까요?'), findsOneWidget);
    await tapText(tester, '내 정보');
    expect(find.text('뽀얀염소님, 어서 와요!'), findsOneWidget);

    // 로그아웃 → 로그인 화면(소개는 다시 안 봄)
    await tapText(tester, '로그아웃');
    expect(find.text('카카오로 시작하기'), findsOneWidget);
    expect(store.tokens, isNull);

    // 같은 카카오 계정으로 다시 로그인하면 가입 단계 없이 홈(지도)
    await tapText(tester, '카카오로 시작하기');
    expect(find.text('우리 동네 염소를 기다려 볼까요?'), findsOneWidget);
  });

  testWidgets('만 14세 미만이면 안내 화면으로 가고 토큰을 지운다', (tester) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 2.625;
    addTearDown(tester.view.reset);
    SharedPreferences.setMockInitialValues({'flags.introSeen': true});

    await reduceMotion(tester);
    final backend = FakeBackend()..forceUnderAge = true;
    final store = MemoryTokenStore();
    await launch(tester, await appOverrides(backend: backend, store: store));

    await tapText(tester, '카카오로 시작하기');
    await tapText(tester, '전체 동의');
    await tapText(tester, '동의하고 계속');
    await tapText(tester, '다음');
    await tapText(tester, '맞아요');

    expect(find.textContaining('만 14세가 되면'), findsOneWidget);
    expect(store.tokens, isNull);
    await tapText(tester, '처음으로');
    expect(find.text('카카오로 시작하기'), findsOneWidget);
  });

  testWidgets('소셜 로그인을 취소하면 로그인 화면에 그대로 머문다', (tester) async {
    SharedPreferences.setMockInitialValues({'flags.introSeen': true});
    await reduceMotion(tester);
    final social = FakeSocialLogin()..kakaoToken = null;
    await launch(
      tester,
      await appOverrides(backend: FakeBackend(), store: MemoryTokenStore(), social: social),
    );
    await tapText(tester, '카카오로 시작하기');
    expect(find.text('카카오로 시작하기'), findsOneWidget);
  });

  testWidgets('토큰은 있는데 서버에 닿지 못하면 다시 시도 화면', (tester) async {
    SharedPreferences.setMockInitialValues({'flags.introSeen': true});
    await reduceMotion(tester);
    final backend = FakeBackend()..offline = true;
    final store = MemoryTokenStore()
      ..tokens = const Tokens(accessToken: 'access:u1', refreshToken: 'r');
    await tester.pumpWidget(
      ProviderScope(
        overrides: await appOverrides(backend: backend, store: store),
        child: const MeeilApp(),
      ),
    );
    await tester.pump();
    await tester.pump();
    expect(find.text('인터넷 연결을 확인해 주세요.'), findsOneWidget);
    expect(find.text('다시 시도'), findsOneWidget);
    // 토큰은 지우지 않는다(오프라인일 뿐)
    expect(store.tokens, isNotNull);
  });
}
