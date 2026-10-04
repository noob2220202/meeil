import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/theme.dart';
import '../../ui/widgets.dart';
import 'rolling_api.dart';
import 'rolling_models.dart';
import 'rolling_texts.dart';
import 'rolling_widgets.dart';

/// 앨범 (SPEC 6): 내가 참여한 마감된 두루마리, 영구 보관
class RollingAlbumScreen extends ConsumerWidget {
  const RollingAlbumScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final album = ref.watch(rollingAlbumProvider);
    return Scaffold(
      backgroundColor: Palette.cream,
      appBar: AppBar(title: const Text('두루마리 앨범')),
      body: album.when(
        loading: () => const Center(child: BobbingGoat(size: 96)),
        error: (e, _) => Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const NoticeBox('앨범을 불러오지 못했어요.'),
                const SizedBox(height: 12),
                ChunkyButton(label: '다시 시도', onPressed: () => ref.invalidate(rollingAlbumProvider)),
              ],
            ),
          ),
        ),
        data: (papers) => papers.isEmpty
            ? const _EmptyAlbum()
            : RefreshIndicator(
                onRefresh: () => ref.refresh(rollingAlbumProvider.future),
                child: ListView.separated(
                  padding: const EdgeInsets.all(16),
                  itemCount: papers.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 12),
                  itemBuilder: (context, i) => _AlbumTile(paper: papers[i]),
                ),
              ),
      ),
    );
  }
}

class _AlbumTile extends StatelessWidget {
  const _AlbumTile({required this.paper});

  final RollingPaper paper;

  @override
  Widget build(BuildContext context) => Semantics(
    button: true,
    label: '${paper.title}, ${periodLabel(paper)}, 한마디 ${paper.entryCount ?? 0}개',
    excludeSemantics: true,
    child: GestureDetector(
      onTap: () => context.push('/rolling/${paper.id}'),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: Palette.outline, width: 2),
        ),
        child: Row(
          children: [
            _RolledScroll(color: paper.level.color),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    paper.title,
                    style: const TextStyle(
                      fontFamily: Fonts.title,
                      fontFamilyFallback: Fonts.fallback,
                      fontSize: 18,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(periodLabel(paper), style: const TextStyle(fontSize: 13)),
                  if (paper.topic != null)
                    Text(
                      '주제: ${paper.topic}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 13),
                    ),
                ],
              ),
            ),
            Pill('한마디 ${paper.entryCount ?? 0}개'),
          ],
        ),
      ),
    ),
  );
}

/// 돌돌 말린 두루마리 썸네일
class _RolledScroll extends StatelessWidget {
  const _RolledScroll({required this.color});

  final Color color;

  @override
  Widget build(BuildContext context) => SizedBox(
    width: 56,
    height: 56,
    child: Stack(
      alignment: Alignment.center,
      children: [
        Container(
          width: 40,
          height: 48,
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(6),
            border: Border.all(color: Palette.outline, width: 2),
          ),
        ),
        const Positioned(top: 0, left: 0, right: 0, child: ScrollRoller(height: 12)),
        const Positioned(bottom: 0, left: 0, right: 0, child: ScrollRoller(height: 12)),
        Container(width: 16, height: 6, color: const Color(0xFFFF8FAB)),
      ],
    ),
  );
}

class _EmptyAlbum extends StatelessWidget {
  const _EmptyAlbum();

  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(28),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const IllustrationImage(Illustration.scroll, size: 130),
          const SizedBox(height: 18),
          Text('앨범이 아직 비었어요', style: Theme.of(context).textTheme.headlineSmall),
          const SizedBox(height: 8),
          const Text(
            '두루마리에 한마디를 남기면\n마감된 뒤 여기에 영원히 보관돼요.',
            textAlign: TextAlign.center,
            style: TextStyle(height: 1.6),
          ),
        ],
      ),
    ),
  );
}
