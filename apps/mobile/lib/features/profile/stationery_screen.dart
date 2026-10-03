import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/theme.dart';
import '../../ui/widgets.dart';
import '../letters/compose_controller.dart';
import '../letters/letter_paper.dart';

/// 편지지 보관함 (SPEC 7.2)
class StationeryScreen extends ConsumerWidget {
  const StationeryScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(stationeryProvider);
    return Scaffold(
      backgroundColor: Palette.cream,
      appBar: AppBar(title: const Text('편지지 보관함')),
      body: s.when(
        loading: () => const Center(child: BobbingGoat(size: 96)),
        error: (e, _) => Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const NoticeBox('편지지를 불러오지 못했어요.'),
                const SizedBox(height: 12),
                ChunkyButton(label: '다시 시도', onPressed: () => ref.invalidate(stationeryProvider)),
              ],
            ),
          ),
        ),
        data: (items) => GridView.builder(
          padding: const EdgeInsets.all(16),
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 2,
            mainAxisSpacing: 14,
            crossAxisSpacing: 14,
            childAspectRatio: 0.68,
          ),
          itemCount: items.length,
          itemBuilder: (context, i) => _Paper(item: items[i]),
        ),
      ),
    );
  }
}

class _Paper extends StatelessWidget {
  const _Paper({required this.item});

  final StationeryItem item;

  @override
  Widget build(BuildContext context) {
    final style = StationeryStyle.of(item.id);
    return Semantics(
      label: '${item.name} 편지지, ${item.owned ? '가지고 있어요' : '잠김, ${item.unlockHint}'}',
      excludeSemantics: true,
      child: Column(
        children: [
          Expanded(
            child: Stack(
              children: [
                Positioned.fill(
                  child: LetterPaper(
                    stationeryId: item.id,
                    child: Text('안녕!\n염소 편으로\n보내요', style: letterTextStyle(style)),
                  ),
                ),
                if (!item.owned)
                  Positioned.fill(
                    child: Container(
                      decoration: BoxDecoration(
                        color: const Color(0xB3FFF8EC),
                        borderRadius: BorderRadius.circular(18),
                      ),
                      padding: const EdgeInsets.all(12),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Icon(Icons.lock_rounded, size: 34, color: Palette.textBrown),
                          const SizedBox(height: 8),
                          Text(
                            item.unlockHint,
                            textAlign: TextAlign.center,
                            style: const TextStyle(fontSize: 13, color: Palette.textBrown),
                          ),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              if (item.owned) ...[
                const Icon(Icons.check_circle_rounded, size: 18, color: Color(0xFF2E9C78)),
                const SizedBox(width: 4),
              ],
              Text(
                item.name,
                style: const TextStyle(
                  fontFamily: Fonts.title,
                  fontFamilyFallback: Fonts.fallback,
                  fontSize: 16,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
