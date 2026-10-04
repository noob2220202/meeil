import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/push_provider.dart';
import '../../app/theme.dart';
import '../letters/letters_api.dart';
import '../letters/mailbox_providers.dart';
import '../letters/mailbox_tab.dart';
import '../map/map_tab.dart';
import '../location/my_region.dart';
import '../profile/profile_tab.dart';
import '../profile/reward_dialogs.dart';
import '../rewards/rewards_api.dart';
import '../rewards/rewards_controller.dart';
import '../rewards/rewards_models.dart';
import '../rolling/rolling_api.dart';
import '../rolling/rolling_tab.dart';

/// 하단 탭: 지도 / 편지함 / 롤링 / 내 정보 (SPEC 10)
class MainShell extends ConsumerStatefulWidget {
  const MainShell({super.key, this.initialTab = 0, this.initialBox = MailBox.inbox, this.mapClock});

  final int initialTab;
  final MailBox initialBox;
  final DateTime Function()? mapClock;

  @override
  ConsumerState<MainShell> createState() => _MainShellState();
}

class _MainShellState extends ConsumerState<MainShell> {
  late int _index = widget.initialTab;

  @override
  void initState() {
    super.initState();
    // 가입을 마친 사용자만 여기 온다 → 푸시 등록
    Future.microtask(() => ref.read(pushServiceProvider).start());
    // 앱을 비운 사이 달성한 업적(받은 편지 100통 등)
    Future.microtask(() => ref.read(unseenAchievementsProvider.notifier).poll());
    _lifecycle = AppLifecycleListener(
      onResume: () => ref.read(unseenAchievementsProvider.notifier).poll(),
    );
  }

  late final AppLifecycleListener _lifecycle;
  bool _celebrating = false;

  @override
  void dispose() {
    _lifecycle.dispose();
    super.dispose();
  }

  Future<void> _celebrate(List<Achievement> list) async {
    if (_celebrating || list.isEmpty || !mounted) return;
    _celebrating = true;
    await showAchievementCelebration(context, list);
    _celebrating = false;
    await ref.read(unseenAchievementsProvider.notifier).dismiss();
  }

  @override
  void didUpdateWidget(MainShell old) {
    super.didUpdateWidget(old);
    // 편지를 맡긴 뒤 /?tab=1&box=sent 로 돌아오는 경우
    if (old.initialTab != widget.initialTab || old.initialBox != widget.initialBox) {
      _index = widget.initialTab;
    }
  }

  @override
  Widget build(BuildContext context) {
    final unread = ref.watch(unreadCountProvider).value ?? 0;
    final attendanceDue = ref.watch(attendanceProvider).value?.checkedToday == false;
    ref.listen(unseenAchievementsProvider, (_, next) => _celebrate(next));
    // 새 시를 방문했거나 편지를 받았으면 업적이 생겼을 수 있다
    ref.listen(myRegionProvider.select((s) => s.regionCode), (prev, next) {
      if (prev != next) ref.read(unseenAchievementsProvider.notifier).poll();
    });
    ref.listen(unreadCountProvider.select((v) => v.value ?? 0), (prev, next) {
      if ((prev ?? 0) < next) ref.read(unseenAchievementsProvider.notifier).poll();
    });
    final tabs = [
      MapTab(clock: widget.mapClock),
      MailboxTab(initialBox: widget.initialBox),
      const RollingTab(),
      const ProfileTab(),
    ];
    return Scaffold(
      body: IndexedStack(
        index: _index,
        children: [
          for (var i = 0; i < tabs.length; i++) TickerMode(enabled: i == _index, child: tabs[i]),
        ],
      ),
      bottomNavigationBar: NavigationBarTheme(
        data: NavigationBarThemeData(
          backgroundColor: Colors.white,
          indicatorColor: Palette.yellow,
          labelTextStyle: WidgetStateProperty.all(
            const TextStyle(
              fontFamily: Fonts.title,
              fontFamilyFallback: Fonts.fallback,
              fontSize: 13,
              color: Palette.textBrown,
            ),
          ),
          iconTheme: WidgetStateProperty.all(const IconThemeData(color: Palette.textBrown)),
        ),
        child: DecoratedBox(
          decoration: const BoxDecoration(
            border: Border(top: BorderSide(color: Palette.outline, width: 2)),
          ),
          child: NavigationBar(
            key: const ValueKey('main-nav'),
            selectedIndex: _index,
            height: 68,
            onDestinationSelected: (i) {
              // 롤링 탭을 열 때마다 이번 장 상태를 새로
              if (i == 2 && _index != 2) ref.invalidate(rollingSummaryProvider);
              if (i == 3 && _index != 3) {
                ref.invalidate(attendanceProvider);
                ref.invalidate(adStatusProvider);
                ref.invalidate(achievementBookProvider);
              }
              setState(() => _index = i);
            },
            destinations: [
              const NavigationDestination(icon: Icon(Icons.map_rounded), label: '지도'),
              NavigationDestination(
                icon: Badge(
                  isLabelVisible: unread > 0,
                  label: Text('$unread'),
                  backgroundColor: const Color(0xFFFF8FAB),
                  child: const Icon(Icons.mail_rounded),
                ),
                label: '편지함',
              ),
              const NavigationDestination(icon: Icon(Icons.history_edu_rounded), label: '롤링'),
              NavigationDestination(
                icon: Badge(
                  key: const ValueKey('profile-badge'),
                  isLabelVisible: attendanceDue,
                  smallSize: 9,
                  backgroundColor: const Color(0xFFFF8FAB),
                  child: const Icon(Icons.person_rounded),
                ),
                label: '내 정보',
              ),
            ],
          ),
        ),
      ),
    );
  }
}
