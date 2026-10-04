import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/theme.dart';
import '../../ui/widgets.dart';
import '../goats/goat_avatar.dart';
import '../goats/hand_availability.dart';
import '../location/my_region.dart';
import 'rolling_api.dart';
import 'rolling_models.dart';
import 'rolling_texts.dart';
import 'rolling_widgets.dart';

/// 롤링 탭 (SPEC 6): 전국·도·시 이번 장 세 개
class RollingTab extends ConsumerWidget {
  const RollingTab({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // 내 시가 바뀌면 도·시 장이 달라진다
    ref.listen(myRegionProvider.select((s) => s.regionCode), (prev, next) {
      if (prev != next) ref.invalidate(rollingSummaryProvider);
    });
    final summary = ref.watch(rollingSummaryProvider);
    final now = ref.watch(clockTickProvider);
    Future<void> refresh() async {
      ref.invalidate(rollingSummaryProvider);
      await ref.read(rollingSummaryProvider.future).catchError((_) => const RollingSummary({}, {}));
    }

    return SafeArea(
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 12, 12, 0),
            child: Row(
              children: [
                Text('롤링페이퍼', style: Theme.of(context).textTheme.headlineMedium),
                const Spacer(),
                OutlinedButton.icon(
                  key: const ValueKey('open-album'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Palette.textBrown,
                    backgroundColor: Colors.white,
                    side: const BorderSide(color: Palette.outline, width: 2),
                  ),
                  onPressed: () => context.push('/rolling/album'),
                  icon: const Icon(Icons.photo_album_rounded, size: 18),
                  label: const Text('앨범'),
                ),
              ],
            ),
          ),
          const Padding(
            padding: EdgeInsets.fromLTRB(20, 4, 20, 8),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text('두루마리 염소가 우리 동네에 오면 한마디 남길 수 있어요.', style: TextStyle(fontSize: 13.5)),
            ),
          ),
          Expanded(
            child: summary.when(
              loading: () => const Center(child: BobbingGoat(size: 96)),
              error: (e, _) => Center(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const NoticeBox('두루마리를 불러오지 못했어요.'),
                      const SizedBox(height: 12),
                      ChunkyButton(label: '다시 시도', onPressed: refresh),
                    ],
                  ),
                ),
              ),
              data: (s) => RefreshIndicator(
                onRefresh: refresh,
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
                  children: [
                    for (final level in RollingLevel.values) ...[
                      if (s.views[level] case final v?)
                        _LevelCard(view: v, now: now)
                      else
                        _NoRegionCard(level: level),
                      const SizedBox(height: 14),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _LevelCard extends StatelessWidget {
  const _LevelCard({required this.view, required this.now});

  final RollingView view;
  final DateTime now;

  @override
  Widget build(BuildContext context) {
    final p = view.paper;
    final status = joinStatusLine(view, now);
    return Semantics(
      button: true,
      label: '${p.title}, ${p.topic ?? '자유 주제'}, 한마디 ${view.entryCount}개, $status',
      excludeSemantics: true,
      child: GestureDetector(
        key: ValueKey('rolling-card-${p.level.api}'),
        onTap: () => context.push('/rolling/${p.id}'),
        child: Container(
          padding: const EdgeInsets.fromLTRB(8, 12, 14, 12),
          decoration: BoxDecoration(
            color: p.level.color,
            borderRadius: BorderRadius.circular(22),
            border: Border.all(color: Palette.outline, width: 2),
            boxShadow: const [BoxShadow(color: Color(0x335A4636), offset: Offset(0, 4))],
          ),
          child: Row(
            children: [
              SizedBox(width: 92, height: 92, child: GoatAvatar(look: p.look, size: 88)),
              const SizedBox(width: 6),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      p.title,
                      style: const TextStyle(
                        fontFamily: Fonts.title,
                        fontFamilyFallback: Fonts.fallback,
                        fontSize: 21,
                        color: Palette.textBrown,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '${p.level.cadence} · ${closesIn(p, now)}',
                      style: const TextStyle(fontSize: 12.5),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      p.topic == null ? '자유 주제' : '주제: ${p.topic}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 14.5, color: Palette.textBrown),
                    ),
                    const SizedBox(height: 8),
                    Pill('한마디 ${view.entryCount}개', icon: Icons.chat_bubble_rounded),
                    const SizedBox(height: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                      decoration: BoxDecoration(
                        color: view.joined
                            ? const Color(0xFFE3F6EC)
                            : view.canJoin
                            ? Palette.yellow
                            : Colors.white,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: Palette.outline, width: 1.5),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            view.joined
                                ? Icons.check_rounded
                                : view.canJoin
                                ? Icons.edit_rounded
                                : Icons.schedule_rounded,
                            size: 15,
                            color: Palette.textBrown,
                          ),
                          const SizedBox(width: 5),
                          Flexible(
                            child: Text(
                              status,
                              style: const TextStyle(fontSize: 13, color: Palette.textBrown),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right_rounded, color: Palette.textBrown),
            ],
          ),
        ),
      ),
    );
  }
}

/// 위치를 몰라 도·시 장을 못 보여 줄 때
class _NoRegionCard extends ConsumerWidget {
  const _NoRegionCard({required this.level});

  final RollingLevel level;

  @override
  Widget build(BuildContext context, WidgetRef ref) => Container(
    padding: const EdgeInsets.fromLTRB(8, 12, 14, 12),
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(22),
      border: Border.all(color: Palette.outline, width: 2),
    ),
    child: Row(
      children: [
        Opacity(
          opacity: 0.55,
          child: SizedBox(width: 92, height: 92, child: GoatAvatar(look: level.look, size: 88)),
        ),
        const SizedBox(width: 6),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '${level.label} 두루마리',
                style: const TextStyle(
                  fontFamily: Fonts.title,
                  fontFamilyFallback: Fonts.fallback,
                  fontSize: 21,
                ),
              ),
              const SizedBox(height: 4),
              const Text('지금 있는 시를 알려 주면 우리 동네 두루마리를 볼 수 있어요.'),
              const SizedBox(height: 8),
              FilledButton.tonalIcon(
                style: FilledButton.styleFrom(
                  backgroundColor: level.color,
                  foregroundColor: Palette.textBrown,
                  side: const BorderSide(color: Palette.outline, width: 1.5),
                ),
                onPressed: () => ref.read(myRegionProvider.notifier).requestAndRefresh(),
                icon: const Icon(Icons.my_location_rounded, size: 18),
                label: const Text('위치 확인하기'),
              ),
            ],
          ),
        ),
      ],
    ),
  );
}
