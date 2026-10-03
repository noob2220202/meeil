import 'package:flutter/material.dart';

/// SPEC 12.4 팔레트
abstract final class Palette {
  static const cream = Color(0xFFFFF8EC);
  static const sky = Color(0xFFCDEBFF);
  static const mint = Color(0xFFBDEBD7);
  static const pink = Color(0xFFFFC9D6);
  static const yellow = Color(0xFFFFE08A);
  static const textBrown = Color(0xFF5A4636);
  static const outline = Color(0xFF7A5C48);
}

/// 폰트 패밀리 (assets/fonts, OFL)
abstract final class Fonts {
  static const title = 'Jua';
  static const body = 'GowunDodum';
  static const handwriting = 'Gaegu';
}

ThemeData buildTheme() {
  final scheme = ColorScheme.fromSeed(
    seedColor: Palette.mint,
    surface: Palette.cream,
    onSurface: Palette.textBrown,
    primary: Palette.outline,
    onPrimary: Colors.white,
  );
  const titleStyle = TextStyle(fontFamily: Fonts.title, color: Palette.textBrown);
  return ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    scaffoldBackgroundColor: Palette.cream,
    fontFamily: Fonts.body,
    textTheme: const TextTheme(
      displaySmall: titleStyle,
      headlineMedium: titleStyle,
      titleLarge: titleStyle,
    ).apply(bodyColor: Palette.textBrown, displayColor: Palette.textBrown),
  );
}
