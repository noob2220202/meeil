import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/theme.dart';
import '../../ui/widgets.dart';
import '../auth/session.dart';
import '../letters/compose_controller.dart';
import '../rewards/rewards_api.dart';
import 'reward_dialogs.dart';

/// 내 정보 탭 (SPEC 7, 10): 포인트·출석·광고·업적·편지지
class ProfileTab extends ConsumerWidget {
  const ProfileTab({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final session = ref.watch(sessionProvider);
    final me = session is SignedIn ? session.me : null;
    final text = Theme.of(context).textTheme;
    final book = ref.watch(achievementBookProvider).value;
    final stationery = ref.watch(stationeryProvider).value;
    return SafeArea(
      child: RefreshIndicator(
        onRefresh: () async {
          ref.invalidate(attendanceProvider);
          ref.invalidate(adStatusProvider);
          ref.invalidate(achievementBookProvider);
          ref.invalidate(stationeryProvider);
          await ref.read(sessionProvider.notifier).refreshMe();
        },
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
          children: [
            Row(
              children: [
                const IllustrationImage(Illustration.goat, size: 76),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(me?.nickname ?? '내 정보', style: text.headlineMedium),
                      const SizedBox(height: 4),
                      _TitleChip(title: me?.title),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            _PointsCard(points: me?.pointsBalance ?? 0),
            const SizedBox(height: 12),
            const Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(child: _AttendanceTile()),
                SizedBox(width: 12),
                Expanded(child: _AdTile()),
              ],
            ),
            const SizedBox(height: 16),
            _MenuTile(
              key: const ValueKey('menu-achievements'),
              icon: Icons.emoji_events_rounded,
              color: Palette.yellow,
              title: '업적 · 칭호',
              trailing: book == null ? null : '${book.achievedCount}/${book.achievements.length}',
              onTap: () => context.push('/achievements'),
            ),
            const SizedBox(height: 10),
            _MenuTile(
              key: const ValueKey('menu-stationery'),
              icon: Icons.auto_stories_rounded,
              color: Palette.sky,
              title: '편지지 보관함',
              trailing: stationery == null
                  ? null
                  : '${stationery.where((s) => s.owned).length}/${stationery.length}',
              onTap: () => context.push('/stationery'),
            ),
            const SizedBox(height: 10),
            _MenuTile(
              key: const ValueKey('menu-settings'),
              icon: Icons.settings_rounded,
              color: Palette.mint,
              title: '설정 · 차단 목록',
              onTap: () => context.push('/settings'),
            ),
            const SizedBox(height: 10),
            _MenuTile(
              key: const ValueKey('menu-notices'),
              icon: Icons.campaign_rounded,
              color: Palette.pink,
              title: '공지사항',
              onTap: () => context.push('/notices'),
            ),
            const SizedBox(height: 24),
            Center(
              child: TextButton.icon(
                onPressed: () => ref.read(sessionProvider.notifier).signOut(),
                icon: const Icon(Icons.logout_rounded, size: 18),
                label: const Text('로그아웃'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _TitleChip extends StatelessWidget {
  const _TitleChip({required this.title});

  final String? title;

  @override
  Widget build(BuildContext context) => Semantics(
    button: true,
    label: title == null ? '칭호 고르기' : '칭호 $title, 바꾸기',
    excludeSemantics: true,
    child: GestureDetector(
      onTap: () => context.push('/achievements'),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          color: title == null ? Colors.white : Palette.yellow,
          borderRadius: BorderRadius.circular(99),
          border: Border.all(color: Palette.outline, width: 1.5),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.workspace_premium_rounded, size: 16, color: Palette.textBrown),
            const SizedBox(width: 4),
            Text(title ?? '칭호를 골라 보세요', style: const TextStyle(fontSize: 13)),
          ],
        ),
      ),
    ),
  );
}

class _PointsCard extends StatelessWidget {
  const _PointsCard({required this.points});

  final int points;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.fromLTRB(18, 14, 8, 14),
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(20),
      border: Border.all(color: Palette.outline, width: 2.5),
      boxShadow: const [BoxShadow(color: Color(0x335A4636), offset: Offset(0, 4))],
    ),
    child: Row(
      children: [
        Container(
          width: 44,
          height: 44,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: Palette.yellow,
            shape: BoxShape.circle,
            border: Border.all(color: Palette.outline, width: 2),
          ),
          child: const Text(
            'P',
            style: TextStyle(
              fontFamily: Fonts.title,
              fontFamilyFallback: Fonts.fallback,
              fontSize: 22,
              color: Palette.textBrown,
            ),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('내 포인트', style: TextStyle(fontSize: 13)),
              Text(
                '${points}P',
                key: const ValueKey('points-balance'),
                style: const TextStyle(
                  fontFamily: Fonts.title,
                  fontFamilyFallback: Fonts.fallback,
                  fontSize: 30,
                  color: Palette.textBrown,
                ),
              ),
              const Text('편지 한 통에 1P가 들어요', style: TextStyle(fontSize: 12)),
            ],
          ),
        ),
        TextButton(
          key: const ValueKey('points-history'),
          onPressed: () => context.push('/points'),
          child: const Text('내역 보기'),
        ),
      ],
    ),
  );
}

/// 출석 칸: 아직이면 바로 출석, 했으면 연속 일수
class _AttendanceTile extends ConsumerWidget {
  const _AttendanceTile();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final a = ref.watch(attendanceProvider);
    final s = a.value;
    final done = s?.checkedToday ?? false;
    return _ActionTile(
      key: const ValueKey('tile-attendance'),
      icon: done ? Icons.event_available_rounded : Icons.calendar_month_rounded,
      color: done ? Palette.mint : Palette.yellow,
      title: done ? '출석 완료' : '출석 체크',
      subtitle: s == null
          ? (a.hasError ? '불러오지 못했어요' : '…')
          : done
          ? '${s.streak}일 연속 출석 중'
          : '+${s.dailyPoints}P 받기',
      onTap: () async {
        if (s != null && !done) await checkInWithCelebration(context, ref);
        if (context.mounted) await context.push('/attendance');
      },
    );
  }
}

/// 광고 칸: 오늘 남은 횟수
class _AdTile extends ConsumerWidget {
  const _AdTile();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final a = ref.watch(adStatusProvider);
    final s = a.value;
    final left = s?.remaining ?? 0;
    return _ActionTile(
      key: const ValueKey('tile-ad'),
      icon: Icons.smart_display_rounded,
      color: s != null && left > 0 ? Palette.pink : const Color(0xFFEFE8E0),
      title: '광고 보고 +${s?.rewardPoints ?? 2}P',
      subtitle: s == null
          ? (a.hasError ? '불러오지 못했어요' : '…')
          : left > 0
          ? '오늘 $left번 더 볼 수 있어요'
          : '오늘은 다 봤어요. 내일 또 만나요!',
      onTap: s == null || left <= 0 ? null : () => watchAdWithFeedback(context, ref),
    );
  }
}

class _ActionTile extends StatelessWidget {
  const _ActionTile({
    super.key,
    required this.icon,
    required this.color,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final IconData icon;
  final Color color;
  final String title;
  final String subtitle;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) => Semantics(
    button: true,
    enabled: onTap != null,
    label: '$title, $subtitle',
    excludeSemantics: true,
    child: GestureDetector(
      onTap: onTap,
      child: Container(
        constraints: const BoxConstraints(minHeight: 118),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: color,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: Palette.outline, width: 2),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, size: 30, color: Palette.textBrown),
            const SizedBox(height: 8),
            Text(
              title,
              style: const TextStyle(
                fontFamily: Fonts.title,
                fontFamilyFallback: Fonts.fallback,
                fontSize: 17,
                color: Palette.textBrown,
              ),
            ),
            const SizedBox(height: 2),
            Text(subtitle, style: const TextStyle(fontSize: 12.5, color: Palette.textBrown)),
          ],
        ),
      ),
    ),
  );
}

class _MenuTile extends StatelessWidget {
  const _MenuTile({
    super.key,
    required this.icon,
    required this.color,
    required this.title,
    required this.onTap,
    this.trailing,
  });

  final IconData icon;
  final Color color;
  final String title;
  final String? trailing;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Material(
    color: Colors.white,
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(16),
      side: const BorderSide(color: Palette.outline, width: 2),
    ),
    clipBehavior: Clip.antiAlias,
    child: ListTile(
      onTap: onTap,
      leading: CircleAvatar(
        backgroundColor: color,
        child: Icon(icon, color: Palette.textBrown),
      ),
      title: Text(
        title,
        style: const TextStyle(
          fontFamily: Fonts.title,
          fontFamilyFallback: Fonts.fallback,
          fontSize: 17,
        ),
      ),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (trailing != null) Text(trailing!, style: const TextStyle(fontSize: 14)),
          const Icon(Icons.chevron_right_rounded),
        ],
      ),
    ),
  );
}
