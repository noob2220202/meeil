// 서버 규칙(apps/server/src/domain/nickname.ts)의 형식 검사 부분을 그대로 옮긴 즉시 피드백용.
// 금칙어·중복은 서버가 판정한다.

const nicknameMin = 2;
const nicknameMax = 10;
final _allowed = RegExp(r'^[가-힣a-zA-Z0-9]+$');

/// 형식 문제가 있으면 안내 문구, 없으면 null
String? localNicknameProblem(String raw) {
  final nick = raw.trim();
  if (nick.isEmpty) return null;
  final len = nick.runes.length;
  if (len < nicknameMin || len > nicknameMax) return '닉네임은 $nicknameMin~$nicknameMax자로 지어 주세요.';
  if (!_allowed.hasMatch(nick)) return '한글, 영문, 숫자만 쓸 수 있어요.';
  return null;
}
