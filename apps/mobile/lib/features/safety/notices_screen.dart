import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/theme.dart';
import '../../ui/widgets.dart';
import '../rolling/rolling_texts.dart' show kstDate;
import 'safety_api.dart';

class NoticesScreen extends ConsumerWidget {
  const NoticesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(noticesProvider);
    return Scaffold(
      backgroundColor: Palette.cream,
      appBar: AppBar(title: const Text('공지사항')),
      body: s.when(
        loading: () => const Center(child: BobbingGoat(size: 96)),
        error: (e, _) => Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const NoticeBox('공지를 불러오지 못했어요.'),
                const SizedBox(height: 12),
                ChunkyButton(label: '다시 시도', onPressed: () => ref.invalidate(noticesProvider)),
              ],
            ),
          ),
        ),
        data: (list) => list.isEmpty
            ? const Center(child: Text('아직 공지가 없어요.'))
            : ListView.separated(
                padding: const EdgeInsets.all(16),
                itemCount: list.length,
                separatorBuilder: (_, _) => const SizedBox(height: 10),
                itemBuilder: (context, i) {
                  final n = list[i];
                  return Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: n.pinned ? const Color(0xFFFFF4C2) : Colors.white,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: Palette.outline, width: 2),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            if (n.pinned) ...[
                              const Icon(Icons.push_pin_rounded, size: 16),
                              const SizedBox(width: 4),
                            ],
                            Expanded(
                              child: Text(
                                n.title,
                                style: const TextStyle(
                                  fontFamily: Fonts.title,
                                  fontFamilyFallback: Fonts.fallback,
                                  fontSize: 17,
                                ),
                              ),
                            ),
                            Text(kstDate(n.publishedAt), style: const TextStyle(fontSize: 12)),
                          ],
                        ),
                        const SizedBox(height: 6),
                        Text(n.body, style: const TextStyle(height: 1.5)),
                      ],
                    ),
                  );
                },
              ),
      ),
    );
  }
}
