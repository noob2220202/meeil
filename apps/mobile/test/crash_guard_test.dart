import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:meeil/core/crash_guard.dart';

void main() {
  test('같은 오류는 한 번, 1분에 5건까지, 길이 제한', () {
    final r = ErrorReporter(enabled: false);
    final stack = StackTrace.current;
    r.report(StateError('같은 오류'), stack);
    r.report(StateError('같은 오류'), stack);
    expect(r.sent, hasLength(1));
    for (var i = 0; i < 10; i++) {
      r.report(StateError('오류 $i ${'x' * 1000}'), stack);
    }
    expect(r.sent, hasLength(5));
    expect((r.sent.last['message']! as String).length, 500);
    expect(r.sent.first.keys, containsAll(['message', 'stack', 'platform', 'mode']));
  });

  testWidgets('넘어진 자리 카드', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(body: Center(child: BrokenPiece())),
      ),
    );
    expect(find.textContaining('염소가 여기를 그리다 넘어졌어요'), findsOneWidget);
  });
}
