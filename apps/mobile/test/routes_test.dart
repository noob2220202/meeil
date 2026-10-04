import 'package:flutter_test/flutter_test.dart';
import 'package:meeil/app/routes.dart';
import 'package:meeil/core/app_flags.dart';
import 'package:meeil/features/auth/me.dart';
import 'package:meeil/features/auth/session.dart';

Me me({bool terms = true, bool birth = true, String? nick = '염소'}) => Me(
  id: 'u',
  nickname: nick,
  status: 'ACTIVE',
  pointsBalance: 0,
  termsAgreed: terms,
  birthDateSet: birth,
  nicknameSet: nick != null,
);

const fresh = AppFlags(introSeen: false, permissionsIntroDone: false);
const seen = AppFlags(introSeen: true, permissionsIntroDone: false);
const done = AppFlags(introSeen: true, permissionsIntroDone: true);

void main() {
  test('복원 중·오프라인은 스플래시', () {
    expect(resolveRedirect(const SessionRestoring(), done, '/'), Routes.splash);
    expect(resolveRedirect(const SessionUnreachable('x'), done, Routes.splash), isNull);
  });

  test('로그아웃 상태: 처음이면 소개, 아니면 로그인, 미성년 거절은 안내', () {
    expect(resolveRedirect(const SignedOut(), fresh, Routes.splash), Routes.intro);
    expect(resolveRedirect(const SignedOut(), seen, Routes.intro), Routes.login);
    expect(resolveRedirect(const SignedOut(), seen, '/'), Routes.login);
    expect(resolveRedirect(const SignedOut(underAge: true), seen, Routes.login), Routes.underAge);
  });

  test('가입 단계 순서: 약관 → 생년월일 → 닉네임 → 권한 → 홈', () {
    expect(
      resolveRedirect(SignedIn(me(terms: false, birth: false, nick: null)), done, '/'),
      Routes.terms,
    );
    expect(
      resolveRedirect(SignedIn(me(birth: false, nick: null)), done, Routes.terms),
      Routes.birth,
    );
    expect(resolveRedirect(SignedIn(me(nick: null)), done, Routes.birth), Routes.nickname);
    expect(resolveRedirect(SignedIn(me()), seen, Routes.nickname), Routes.permissions);
    expect(resolveRedirect(SignedIn(me()), done, Routes.permissions), Routes.home);
  });

  test('가입을 마친 사용자는 로그인 전 화면에 머물 수 없다', () {
    expect(resolveRedirect(SignedIn(me()), done, Routes.login), Routes.home);
    expect(resolveRedirect(SignedIn(me()), done, '/'), isNull);
  });

  test('약관 본문은 언제나 열람 가능', () {
    expect(resolveRedirect(const SignedOut(), fresh, '/docs/terms'), isNull);
    expect(resolveRedirect(SignedIn(me(terms: false)), done, '/docs/privacy'), isNull);
  });
}
