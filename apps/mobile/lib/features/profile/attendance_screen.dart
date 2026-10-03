import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/theme.dart';
import '../../ui/widgets.dart';
import '../rewards/rewards_api.dart';
import '../rewards/rewards_models.dart';
import 'reward_dialogs.dart';

/// 출석 체크 (SPEC 7.1): 이번 달 달력 + 연속 출석 발자국
class AttendanceScreen extends ConsumerWidget {
  const AttendanceScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final a = ref.watch(attendanceProvider);
    return Scaffold(
      backgroundColor: Palette.cream,
      appBar: AppBar(title: const Text('출석 체크')),
      body: a.when(
        loading: () => const Center(child: BobbingGoat(size: 96)),
        error: (e, _) => Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const NoticeBox('출석 정보를 불러오지 못했어요.'),
                const SizedBox(height: 12),
                ChunkyButton(label: '다시 시도', onPressed: () => ref.invalidate(attendanceProvider)),
              ],
            ),
          ),
        ),
        data: (s) => ListView(
          padding: const EdgeInsets.all(16),
          children: [
            _StreakCard(status: s),
            const SizedBox(height: 14),
            _Calendar(status: s),
            const SizedBox(height: 16),
            if (s.checkedToday)
              const NoticeBox(
                '오늘 출석을 마쳤어요. 내일 또 만나요!',
                color: Palette.mint,
                icon: Icons.check_circle_rounded,
              )
            else
              ChunkyButton(
                key: const ValueKey('check-in'),
                label: '오늘 출석하기 +${s.dailyPoints}P',
                color: Palette.yellow,
                onPressed: () => checkInWithCelebration(context, ref),
              ),
            const SizedBox(height: 12),
            Text(
              '하루 한 번 ${s.dailyPoints}P, ${s.streakDays}일 연속이면 ${s.streakBonus}P를 더 받아요.\n'
              '날짜는 한국 시각 자정에 바뀌어요.',
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 13, height: 1.5),
            ),
          ],
        ),
      ),
    );
  }
}

/// 연속 출석 7칸(발자국)
class _StreakCard extends StatelessWidget {
  const _StreakCard({required this.status});

  final AttendanceStatus status;

  @override
  Widget build(BuildContext context) {
    final s = status;
    final filled = s.streak == 0 ? 0 : ((s.streak - 1) % s.streakDays) + 1;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Palette.yellow,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Palette.outline, width: 2.5),
      ),
      child: Column(
        children: [
          Text(
            s.streak == 0 ? '오늘부터 연속 출석!' : '${s.streak}일 연속 출석 중',
            style: const TextStyle(
              fontFamily: Fonts.title,
              fontFamilyFallback: Fonts.fallback,
              fontSize: 22,
              color: Palette.textBrown,
            ),
          ),
          const SizedBox(height: 4),
          Text('지금까지 모두 ${s.totalDays}일 왔어요', style: const TextStyle(fontSize: 13)),
          const SizedBox(height: 12),
          Semantics(
            label: '연속 출석 ${s.streakDays}칸 중 $filled칸',
            excludeSemantics: true,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                for (var i = 0; i < s.streakDays; i++)
                  _Hoof(on: i < filled, last: i == s.streakDays - 1, bonus: s.streakBonus),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _Hoof extends StatelessWidget {
  const _Hoof({required this.on, required this.last, required this.bonus});

  final bool on;
  final bool last;
  final int bonus;

  @override
  Widget build(BuildContext context) => Column(
    children: [
      Container(
        width: 36,
        height: 36,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: on ? Colors.white : const Color(0x66FFFFFF),
          shape: BoxShape.circle,
          border: Border.all(color: Palette.outline, width: on ? 2 : 1.2),
        ),
        child: on
            ? const Icon(Icons.pets_rounded, size: 20, color: Color(0xFF8C6A55))
            : last
            ? const Icon(Icons.card_giftcard_rounded, size: 18, color: Color(0xFFE08A5C))
            : null,
      ),
      const SizedBox(height: 2),
      SizedBox(
        height: 14,
        child: last ? Text('+${bonus}P', style: const TextStyle(fontSize: 10.5)) : null,
      ),
    ],
  );
}

class _Calendar extends StatelessWidget {
  const _Calendar({required this.status});

  final AttendanceStatus status;

  @override
  Widget build(BuildContext context) {
    final parts = status.month.split('-').map(int.parse).toList();
    final y = parts[0];
    final m = parts[1];
    final first = DateTime.utc(y, m);
    final daysInMonth = DateTime.utc(y, m + 1, 0).day;
    final lead = first.weekday % 7; // 일요일 시작
    String key(int d) => '${status.month}-${d.toString().padLeft(2, '0')}';
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 14, 12, 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Palette.outline, width: 2),
      ),
      child: Column(
        children: [
          Text(
            '$y년 $m월',
            style: const TextStyle(
              fontFamily: Fonts.title,
              fontFamilyFallback: Fonts.fallback,
              fontSize: 18,
            ),
          ),
          const SizedBox(height: 10),
          GridView.count(
            crossAxisCount: 7,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            mainAxisSpacing: 6,
            crossAxisSpacing: 4,
            children: [
              for (final (i, w) in ['일', '월', '화', '수', '목', '금', '토'].indexed)
                Center(
                  child: Text(
                    w,
                    style: TextStyle(
                      fontSize: 12.5,
                      color: i == 0 ? const Color(0xFFE0607E) : Palette.textBrown,
                    ),
                  ),
                ),
              for (var i = 0; i < lead; i++) const SizedBox.shrink(),
              for (var d = 1; d <= daysInMonth; d++)
                _Day(day: d, stamped: status.days.contains(key(d)), today: key(d) == status.today),
            ],
          ),
        ],
      ),
    );
  }
}

class _Day extends StatelessWidget {
  const _Day({required this.day, required this.stamped, required this.today});

  final int day;
  final bool stamped;
  final bool today;

  @override
  Widget build(BuildContext context) => Semantics(
    label: '$day일${stamped ? ', 출석' : ''}${today ? ', 오늘' : ''}',
    excludeSemantics: true,
    child: Container(
      decoration: BoxDecoration(
        color: stamped ? Palette.mint : null,
        shape: BoxShape.circle,
        border: today ? Border.all(color: const Color(0xFFE08A5C), width: 2) : null,
      ),
      alignment: Alignment.center,
      child: stamped
          ? Stack(
              alignment: Alignment.center,
              children: [
                Icon(
                  Icons.pets_rounded,
                  size: 24,
                  color: Palette.textBrown.withValues(alpha: 0.18),
                ),
                Text('$day', style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700)),
              ],
            )
          : Text('$day', style: const TextStyle(fontSize: 13)),
    ),
  );
}
