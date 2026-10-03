import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/push_provider.dart';
import '../../app/theme.dart';
import '../../ui/widgets.dart';
import '../auth/session.dart';
import '../letters/letters_api.dart';
import '../letters/mailbox_providers.dart';
import '../letters/mailbox_tab.dart';
import '../map/map_tab.dart';

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
    final tabs = [
      MapTab(clock: widget.mapClock),
      MailboxTab(initialBox: widget.initialBox),
      const _ComingSoon(
        illustration: Illustration.scroll,
        title: '롤링페이퍼는 곧 열려요',
        body: '두루마리 염소가 오면\n우리 동네 사람들과 한 장을 채워요.',
      ),
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
            onDestinationSelected: (i) => setState(() => _index = i),
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
              const NavigationDestination(icon: Icon(Icons.person_rounded), label: '내 정보'),
            ],
          ),
        ),
      ),
    );
  }
}

class _ComingSoon extends StatelessWidget {
  const _ComingSoon({required this.illustration, required this.title, required this.body});

  final Illustration illustration;
  final String title;
  final String body;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return SafeArea(
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              IllustrationImage(illustration, size: 140),
              const SizedBox(height: 20),
              Text(title, style: text.headlineMedium),
              const SizedBox(height: 10),
              Text(body, textAlign: TextAlign.center, style: text.bodyLarge?.copyWith(height: 1.6)),
            ],
          ),
        ),
      ),
    );
  }
}

/// 내 정보(설정은 이후 단계에서 채운다)
class ProfileTab extends ConsumerWidget {
  const ProfileTab({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final session = ref.watch(sessionProvider);
    final me = session is SignedIn ? session.me : null;
    final text = Theme.of(context).textTheme;
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const SizedBox(height: 12),
            const Center(child: IllustrationImage(Illustration.goat, size: 120)),
            const SizedBox(height: 12),
            Text(
              me?.nickname != null ? '${me!.nickname}님, 어서 와요!' : '내 정보',
              textAlign: TextAlign.center,
              style: text.headlineMedium,
            ),
            const SizedBox(height: 20),
            if (me != null)
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(color: Palette.outline, width: 2.5),
                ),
                child: Row(
                  children: [
                    const Text('내 포인트', style: TextStyle(fontSize: 16)),
                    const Spacer(),
                    Text(
                      '${me.pointsBalance}P',
                      style: const TextStyle(
                        fontFamily: Fonts.title,
                        fontFamilyFallback: Fonts.fallback,
                        fontSize: 22,
                      ),
                    ),
                  ],
                ),
              ),
            const Spacer(),
            TextButton.icon(
              onPressed: () => ref.read(sessionProvider.notifier).signOut(),
              icon: const Icon(Icons.logout_rounded, size: 18),
              label: const Text('로그아웃'),
            ),
          ],
        ),
      ),
    );
  }
}
