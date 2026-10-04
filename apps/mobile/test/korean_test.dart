import 'package:flutter_test/flutter_test.dart';
import 'package:meeil/core/korean.dart';

void main() {
  test('이/가', () {
    expect(iGa('메롱이'), '메롱이가');
    expect(iGa('음메'), '음메가');
    expect(iGa('콩'), '콩이');
    expect(iGa('보리, 두부'), '보리, 두부가');
  });
  test('으로/로', () {
    expect(euro('제주시'), '제주시로');
    expect(euro('울릉군'), '울릉군으로');
    expect(euro('서울'), '서울로'); // ㄹ 받침
  });
  test('을/를', () {
    expect(eulReul('편지'), '편지를');
    expect(eulReul('두루마리'), '두루마리를');
    expect(eulReul('염소 일정'), '염소 일정을');
  });
}
