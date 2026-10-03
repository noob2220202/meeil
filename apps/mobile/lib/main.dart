import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'app/app.dart';
import 'core/app_flags.dart';
import 'features/auth/social_login.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  SdkSocialLogin.initKakao();
  final prefs = await SharedPreferences.getInstance();
  runApp(
    ProviderScope(
      overrides: [sharedPrefsProvider.overrideWithValue(prefs)],
      child: const MeeilApp(),
    ),
  );
}
