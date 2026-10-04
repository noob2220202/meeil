import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/theme.dart';
import '../../ui/widgets.dart';
import '../letters/mailbox_tab.dart' show formatWhen;
import '../goats/hand_availability.dart';
import '../rewards/rewards_api.dart';
import '../rewards/rewards_models.dart';

class LedgerState {
  const LedgerState(this.entries, this.nextCursor, {this.loadingMore = false});
  final List<LedgerEntry> entries;
  final String? nextCursor;
  final bool loadingMore;
}

class LedgerController extends AsyncNotifier<LedgerState> {
  @override
  Future<LedgerState> build() async {
    final p = await ref.read(rewardsApiProvider).history();
    return LedgerState(p.entries, p.nextCursor);
  }

  Future<void> loadMore() async {
    final cur = state.value;
    if (cur == null || cur.nextCursor == null || cur.loadingMore) return;
    state = AsyncData(LedgerState(cur.entries, cur.nextCursor, loadingMore: true));
    try {
      final p = await ref.read(rewardsApiProvider).history(cursor: cur.nextCursor);
      state = AsyncData(LedgerState([...cur.entries, ...p.entries], p.nextCursor));
    } catch (_) {
      state = AsyncData(LedgerState(cur.entries, cur.nextCursor));
    }
  }
}

final ledgerProvider = AsyncNotifierProvider.autoDispose<LedgerController, LedgerState>(
  LedgerController.new,
  retry: (_, _) => null,
);

IconData _iconFor(String reason) => switch (reason) {
  'SIGNUP_BONUS' => Icons.card_giftcard_rounded,
  'ATTENDANCE' || 'ATTENDANCE_STREAK' => Icons.event_available_rounded,
  'AD_REWARD' => Icons.smart_display_rounded,
  'ACHIEVEMENT' => Icons.emoji_events_rounded,
  'LETTER_SEND' => Icons.mail_rounded,
  'LETTER_REFUND' => Icons.undo_rounded,
  _ => Icons.tune_rounded,
};

/// 포인트 내역(서버 원장 그대로)
class PointsHistoryScreen extends ConsumerWidget {
  const PointsHistoryScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(ledgerProvider);
    final now = ref.watch(clockTickProvider);
    return Scaffold(
      backgroundColor: Palette.cream,
      appBar: AppBar(title: const Text('포인트 내역')),
      body: s.when(
        loading: () => const Center(child: BobbingGoat(size: 96)),
        error: (e, _) => Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const NoticeBox('내역을 불러오지 못했어요.'),
                const SizedBox(height: 12),
                ChunkyButton(label: '다시 시도', onPressed: () => ref.invalidate(ledgerProvider)),
              ],
            ),
          ),
        ),
        data: (st) => st.entries.isEmpty
            ? const Center(child: Text('아직 포인트 내역이 없어요.'))
            : NotificationListener<ScrollNotification>(
                onNotification: (n) {
                  if (n.metrics.extentAfter < 300) ref.read(ledgerProvider.notifier).loadMore();
                  return false;
                },
                child: ListView.separated(
                  padding: const EdgeInsets.all(16),
                  itemCount: st.entries.length + (st.loadingMore ? 1 : 0),
                  separatorBuilder: (_, _) => const SizedBox(height: 8),
                  itemBuilder: (context, i) {
                    if (i >= st.entries.length) {
                      return const Center(child: CircularProgressIndicator());
                    }
                    final e = st.entries[i];
                    final plus = e.delta > 0;
                    return Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(color: Palette.outline, width: 1.5),
                      ),
                      child: Row(
                        children: [
                          CircleAvatar(
                            radius: 18,
                            backgroundColor: plus ? Palette.mint : Palette.pink,
                            child: Icon(_iconFor(e.reason), size: 19, color: Palette.textBrown),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(e.label, style: const TextStyle(fontSize: 15)),
                                Text(
                                  '${formatWhen(e.createdAt, now)} · 남은 ${e.balanceAfter}P',
                                  style: const TextStyle(fontSize: 12),
                                ),
                              ],
                            ),
                          ),
                          Text(
                            '${plus ? '+' : ''}${e.delta}P',
                            style: TextStyle(
                              fontFamily: Fonts.title,
                              fontFamilyFallback: Fonts.fallback,
                              fontSize: 19,
                              color: plus ? const Color(0xFF2E9C78) : const Color(0xFFD0587A),
                            ),
                          ),
                        ],
                      ),
                    );
                  },
                ),
              ),
      ),
    );
  }
}
