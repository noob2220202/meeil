// 한국어 표기 도우미

/// 마지막 글자에 받침이 있는지(한글이 아니면 숫자·영문 끝소리를 대략 판단)
bool hasBatchim(String word) {
  if (word.isEmpty) return false;
  final c = word.runes.last;
  if (c >= 0xAC00 && c <= 0xD7A3) return (c - 0xAC00) % 28 != 0;
  // 숫자: 0 1 3 6 7 8 은 받침 있음(영, 일, 삼, 육, 칠, 팔)
  const digitBatchim = {0x30, 0x31, 0x33, 0x36, 0x37, 0x38};
  if (c >= 0x30 && c <= 0x39) return digitBatchim.contains(c);
  return false;
}

/// 받침이 ㄹ인지(으로/로 구분용)
bool _rieulBatchim(String word) {
  if (word.isEmpty) return false;
  final c = word.runes.last;
  return c >= 0xAC00 && c <= 0xD7A3 && (c - 0xAC00) % 28 == 8;
}

/// 이/가
String iGa(String word) => '$word${hasBatchim(word) ? '이' : '가'}';

/// 을/를
String eulReul(String word) => '$word${hasBatchim(word) ? '을' : '를'}';

/// 으로/로 (ㄹ 받침은 "로")
String euro(String word) => '$word${hasBatchim(word) && !_rieulBatchim(word) ? '으로' : '로'}';

/// 여러 이름을 쉼표로 이은 뒤 이/가
String namesIGa(List<String> names) => iGa(names.join(', '));
