import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'router.dart';
import 'theme.dart';

/// 앱 전체 언어 설정(한국어). 테스트·스크린샷에서도 같은 값을 쓴다.
const appLocale = Locale('ko', 'KR');
const appLocalizationsDelegates = GlobalMaterialLocalizations.delegates;

class MeeilApp extends ConsumerWidget {
  const MeeilApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return MaterialApp.router(
      title: '메에일',
      debugShowCheckedModeBanner: false,
      theme: buildTheme(),
      routerConfig: ref.watch(routerProvider),
      locale: appLocale,
      supportedLocales: const [appLocale],
      localizationsDelegates: appLocalizationsDelegates,
    );
  }
}
