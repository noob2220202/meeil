import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/theme.dart';
import '../../core/api_client.dart';
import '../../ui/widgets.dart';
import '../rewards/rewards_api.dart';
import '../rewards/rewards_controller.dart';
import '../rewards/rewards_models.dart';

/// 업적·칭호 (SPEC 7.3)
class AchievementsScreen extends ConsumerWidget {
  const AchievementsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(achievementBookProvider);
    return Scaffold(
      backgroundColor: Palette.cream,
      appBar: AppBar(title: const Text('업적 · 칭호')),
      body: s.when(
        loading: () => const Center(child: BobbingGoat(size: 96)),
        error: (e, _) => Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const NoticeBox('업적을 불러오지 못했어요.'),
                const SizedBox(height: 12),
                ChunkyButton(
                  label: '다시 시도',
                  onPressed: () => ref.invalidate(achievementBookProvider),
                ),
              ],
            ),
          ),
        ),
        data: (book) {
          // 달성한 것 먼저, 그다음 많이 진행된 순
          final list = [...book.achievements]
            ..sort((a, b) {
              if (a.achieved != b.achieved) return a.achieved ? -1 : 1;
              return b.progress.compareTo(a.progress);
            });
          final titled = book.achievements.where((a) => a.achieved && a.titleText != null);
          final current = book.achievements
              .where((a) => a.id == book.titleAchievementId)
              .firstOrNull;
          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Palette.yellow,
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: Palette.outline, width: 2.5),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.emoji_events_rounded, size: 40, color: Palette.textBrown),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '업적 ${book.achievedCount} / ${book.achievements.length}',
                            style: const TextStyle(
                              fontFamily: Fonts.title,
                              fontFamilyFallback: Fonts.fallback,
                              fontSize: 22,
                            ),
                          ),
                          Text(
                            current?.titleText == null
                                ? (titled.isEmpty
                                      ? '칭호가 있는 업적을 달성하면 닉네임 옆에 달 수 있어요'
                                      : '아래에서 칭호를 골라 달아 보세요')
                                : '지금 칭호: ${current!.titleText}',
                            style: const TextStyle(fontSize: 13),
                          ),
                        ],
                      ),
                    ),
                    if (current != null)
                      TextButton(
                        onPressed: () => _setTitle(context, ref, null),
                        child: const Text('떼기'),
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 14),
              for (final a in list) ...[
                _AchievementCard(
                  a: a,
                  wearing: a.id == book.titleAchievementId,
                  onWear: a.achieved && a.titleText != null && a.id != book.titleAchievementId
                      ? () => _setTitle(context, ref, a.id)
                      : null,
                ),
                const SizedBox(height: 10),
              ],
            ],
          );
        },
      ),
    );
  }

  Future<void> _setTitle(BuildContext context, WidgetRef ref, String? id) async {
    try {
      await ref.read(rewardsActionsProvider).setTitle(id);
    } on ApiException catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
      }
    }
  }
}

class _AchievementCard extends StatelessWidget {
  const _AchievementCard({required this.a, required this.wearing, required this.onWear});

  final Achievement a;
  final bool wearing;
  final VoidCallback? onWear;

  @override
  Widget build(BuildContext context) {
    final rewards = [
      if (a.rewardPoints > 0) '+${a.rewardPoints}P',
      if (a.titleText != null) '칭호 「${a.titleText}」',
      if (a.stationeryName != null) '편지지 「${a.stationeryName}」',
    ];
    return Semantics(
      container: true,
      label:
          '${a.name}, ${a.description}, ${a.achieved ? '달성' : '${a.current}/${a.target}'}'
          '${rewards.isEmpty ? '' : ', 보상 ${rewards.join(', ')}'}',
      child: Container(
        key: ValueKey('achievement-${a.id}'),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: a.achieved ? Colors.white : const Color(0xFFFBF7F1),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: wearing ? const Color(0xFFE0A100) : Palette.outline,
            width: wearing ? 3 : 1.5,
          ),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _Badge(achieved: a.achieved),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    a.name,
                    style: TextStyle(
                      fontFamily: Fonts.title,
                      fontFamilyFallback: Fonts.fallback,
                      fontSize: 17,
                      color: a.achieved
                          ? Palette.textBrown
                          : Palette.textBrown.withValues(alpha: 0.75),
                    ),
                  ),
                  Text(a.description, style: const TextStyle(fontSize: 13)),
                  if (!a.achieved && a.target > 1) ...[
                    const SizedBox(height: 6),
                    Row(
                      children: [
                        Expanded(
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(99),
                            child: LinearProgressIndicator(
                              value: a.progress,
                              minHeight: 8,
                              color: const Color(0xFF3FBF9B),
                              backgroundColor: const Color(0xFFEDE6DD),
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text('${a.current}/${a.target}', style: const TextStyle(fontSize: 12)),
                      ],
                    ),
                  ],
                  if (rewards.isNotEmpty) ...[
                    const SizedBox(height: 6),
                    Wrap(
                      spacing: 5,
                      runSpacing: 4,
                      children: [
                        for (final r in rewards)
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                            decoration: BoxDecoration(
                              color: a.achieved ? Palette.yellow : const Color(0xFFF1ECE6),
                              borderRadius: BorderRadius.circular(99),
                            ),
                            child: Text(r, style: const TextStyle(fontSize: 11.5)),
                          ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
            if (wearing)
              const Padding(
                padding: EdgeInsets.only(left: 6),
                child: Text('다는 중', style: TextStyle(fontSize: 12.5, color: Color(0xFFB07800))),
              )
            else if (onWear != null)
              TextButton(onPressed: onWear, child: const Text('칭호 달기')),
          ],
        ),
      ),
    );
  }
}

class _Badge extends StatelessWidget {
  const _Badge({required this.achieved});

  final bool achieved;

  @override
  Widget build(BuildContext context) => Container(
    width: 44,
    height: 44,
    decoration: BoxDecoration(
      color: achieved ? Palette.yellow : const Color(0xFFEDE6DD),
      shape: BoxShape.circle,
      border: Border.all(color: Palette.outline, width: 2),
    ),
    child: Icon(
      achieved ? Icons.star_rounded : Icons.lock_rounded,
      color: achieved ? const Color(0xFFE08A5C) : Palette.textBrown.withValues(alpha: 0.45),
      size: achieved ? 28 : 20,
    ),
  );
}
