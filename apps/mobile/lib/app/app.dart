import 'package:flutter/material.dart';

import 'router.dart';
import 'theme.dart';

class MeeilApp extends StatelessWidget {
  const MeeilApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp.router(
      title: '메에일',
      debugShowCheckedModeBanner: false,
      theme: buildTheme(),
      routerConfig: appRouter,
    );
  }
}
