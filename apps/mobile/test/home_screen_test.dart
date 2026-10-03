import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:meeil/app/app.dart';
import 'package:meeil/data/regions.dart';

void main() {
  testWidgets('지역 데이터가 로드되면 개수를 보여준다', (tester) async {
    final data = RegionData(version: 't', provinces: const [], regions: const []);
    await tester.pumpWidget(ProviderScope(
      overrides: [regionDataProvider.overrideWith((ref) async => data)],
      child: const MeeilApp(),
    ));
    expect(find.text('메에일'), findsOneWidget);
    await tester.pumpAndSettle();
    expect(find.text('0개 시도 · 0개 시'), findsOneWidget);
  });

  testWidgets('로드 실패 시 다시 시도 버튼을 보여준다', (tester) async {
    await tester.pumpWidget(ProviderScope(
      overrides: [regionDataProvider.overrideWith((ref) async => throw Exception('x'))],
      child: const MeeilApp(),
    ));
    await tester.pumpAndSettle();
    expect(find.textContaining('다시 시도'), findsOneWidget);
    expect(find.byType(TextButton), findsOneWidget);
  });
}
