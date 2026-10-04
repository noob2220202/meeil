import 'package:flutter_test/flutter_test.dart';
import 'package:meeil/features/onboarding/nickname_rules.dart';

void main() {
  test('서버와 같은 형식 규칙', () {
    expect(localNicknameProblem(''), isNull);
    expect(localNicknameProblem('가'), contains('2~10자'));
    expect(localNicknameProblem('가나다라마바사아자차카'), contains('2~10자'));
    expect(localNicknameProblem('ㅋㅋ'), contains('한글, 영문, 숫자'));
    expect(localNicknameProblem('염소 편지'), contains('한글, 영문, 숫자'));
    expect(localNicknameProblem('뽀얀염소99'), isNull);
  });
}
