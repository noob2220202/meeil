import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 기기에 남기는 단순 플래그(온보딩 소개를 봤는지, 권한 안내를 마쳤는지)
class AppFlags {
  const AppFlags({required this.introSeen, required this.permissionsIntroDone});

  final bool introSeen;
  final bool permissionsIntroDone;
}

/// main()에서 SharedPreferences 인스턴스를 주입한다(테스트에서는 mock 값).
final sharedPrefsProvider = Provider<SharedPreferences>(
  (ref) => throw UnimplementedError('sharedPrefsProvider는 main에서 override해야 합니다'),
);

class AppFlagsController extends Notifier<AppFlags> {
  static const _intro = 'flags.introSeen';
  static const _permissions = 'flags.permissionsIntroDone';

  @override
  AppFlags build() {
    final prefs = ref.watch(sharedPrefsProvider);
    return AppFlags(
      introSeen: prefs.getBool(_intro) ?? false,
      permissionsIntroDone: prefs.getBool(_permissions) ?? false,
    );
  }

  Future<void> markIntroSeen() async {
    await ref.read(sharedPrefsProvider).setBool(_intro, true);
    state = AppFlags(introSeen: true, permissionsIntroDone: state.permissionsIntroDone);
  }

  Future<void> markPermissionsIntroDone() async {
    await ref.read(sharedPrefsProvider).setBool(_permissions, true);
    state = AppFlags(introSeen: state.introSeen, permissionsIntroDone: true);
  }
}

final appFlagsProvider = NotifierProvider<AppFlagsController, AppFlags>(AppFlagsController.new);
