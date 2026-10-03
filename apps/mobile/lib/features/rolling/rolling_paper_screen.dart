import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/theme.dart';
import '../../core/api_client.dart';
import '../../ui/widgets.dart';
import '../goats/goat_avatar.dart';
import '../goats/hand_availability.dart';
import '../letters/compose_screen.dart' show StickerTray;
import '../letters/letter_models.dart';
import '../letters/letter_paper.dart';
import 'rolling_api.dart';
import 'rolling_models.dart';
import 'rolling_texts.dart';
import 'rolling_widgets.dart';

/// 두루마리 한 장: 위·아래 막대 사이에 한마디 쪽지들
class RollingPaperScreen extends ConsumerWidget {
  const RollingPaperScreen({super.key, required this.id});

  final String id;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(rollingPaperProvider(id));
    final now = ref.watch(clockTickProvider);
    final controller = ref.read(rollingPaperProvider(id).notifier);
    return Scaffold(
      backgroundColor: Palette.cream,
      appBar: AppBar(title: Text(state.value?.paper.title ?? '두루마리')),
      body: state.when(
        loading: () => const Center(child: BobbingGoat(size: 96)),
        error: (e, _) => Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                NoticeBox(e is ApiException ? e.message : '두루마리를 불러오지 못했어요.'),
                const SizedBox(height: 12),
                if (e is! ApiException || e.statusCode != 403)
                  ChunkyButton(label: '다시 시도', onPressed: controller.refresh),
              ],
            ),
          ),
        ),
        data: (v) => Column(
          children: [
            Expanded(
              child: RefreshIndicator(
                onRefresh: controller.refresh,
                child: _Scroll(view: v, now: now),
              ),
            ),
            _JoinBar(view: v, now: now, onJoin: () => _openJoin(context, v)),
          ],
        ),
      ),
    );
  }

  Future<void> _openJoin(BuildContext context, RollingView v) => showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Palette.cream,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
    ),
    builder: (_) => JoinSheet(paper: v.paper),
  );
}

class _Scroll extends StatelessWidget {
  const _Scroll({required this.view, required this.now});

  final RollingView view;
  final DateTime now;

  @override
  Widget build(BuildContext context) {
    final p = view.paper;
    return LayoutBuilder(
      builder: (context, box) {
        final noteW = (box.maxWidth - 88 - 14 - 4) / 2;
        return ListView(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 20),
          children: [
            const ScrollRoller(),
            Container(
              margin: const EdgeInsets.symmetric(horizontal: 8),
              padding: const EdgeInsets.fromLTRB(14, 16, 14, 24),
              decoration: BoxDecoration(
                color: const Color(0xFFFFFCF4),
                border: Border.symmetric(
                  vertical: BorderSide(color: p.level.color.withValues(alpha: 0.9), width: 6),
                ),
              ),
              child: Column(
                children: [
                  GoatAvatar(look: p.look, size: 92),
                  Text(
                    p.title,
                    style: const TextStyle(
                      fontFamily: Fonts.title,
                      fontFamilyFallback: Fonts.fallback,
                      fontSize: 24,
                      color: Palette.textBrown,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    view.closed ? periodLabel(p) : '${periodLabel(p)} · ${closesIn(p, now)}',
                    style: const TextStyle(fontSize: 13),
                  ),
                  const SizedBox(height: 10),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                    decoration: BoxDecoration(
                      color: p.level.color,
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: Palette.outline, width: 1.5),
                    ),
                    child: Text(
                      p.topic == null ? '자유 주제 — 무엇이든 한마디!' : '주제: ${p.topic}',
                      textAlign: TextAlign.center,
                      style: const TextStyle(fontSize: 14.5, color: Palette.textBrown),
                    ),
                  ),
                  const SizedBox(height: 20),
                  if (view.entries.isEmpty)
                    _EmptyPaper(view: view)
                  else
                    Wrap(
                      spacing: 14,
                      runSpacing: 22,
                      alignment: WrapAlignment.center,
                      children: [for (final e in view.entries) NoteCard(entry: e, width: noteW)],
                    ),
                ],
              ),
            ),
            const ScrollRoller(),
          ],
        );
      },
    );
  }
}

class _EmptyPaper extends StatelessWidget {
  const _EmptyPaper({required this.view});

  final RollingView view;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 28),
    child: Column(
      children: [
        Icon(Icons.edit_note_rounded, size: 44, color: Palette.textBrown.withValues(alpha: 0.5)),
        const SizedBox(height: 8),
        Text(
          view.closed
              ? '조용히 지나간 두루마리예요.'
              : view.canJoin
              ? '아직 비어 있어요.\n첫 한마디를 남겨 볼까요?'
              : '아직 비어 있어요.\n염소가 오면 첫 한마디를 남겨 주세요.',
          textAlign: TextAlign.center,
          style: const TextStyle(height: 1.6),
        ),
      ],
    ),
  );
}

class _JoinBar extends StatelessWidget {
  const _JoinBar({required this.view, required this.now, required this.onJoin});

  final RollingView view;
  final DateTime now;
  final VoidCallback onJoin;

  @override
  Widget build(BuildContext context) {
    final Widget child;
    if (view.canJoin) {
      child = ChunkyButton(
        key: const ValueKey('rolling-join'),
        label: '한마디 남기기',
        color: Palette.yellow,
        leading: const Icon(Icons.edit_rounded, color: Palette.textBrown),
        onPressed: onJoin,
      );
    } else if (view.closed) {
      child = NoticeBox(
        view.joined ? '마감된 두루마리예요. 앨범에 영원히 보관돼요.' : '마감된 두루마리예요.',
        color: Colors.white,
        icon: Icons.inventory_2_rounded,
      );
    } else if (view.joined) {
      child = const NoticeBox(
        '한마디 남겼어요! 마감되면 앨범에 보관돼요.',
        color: Color(0xFFE3F6EC),
        icon: Icons.check_circle_rounded,
      );
    } else {
      child = NoticeBox(
        joinStatusLine(view, now),
        color: Colors.white,
        icon: Icons.schedule_rounded,
      );
    }
    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(top: BorderSide(color: Palette.outline, width: 2)),
      ),
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
      child: SafeArea(top: false, child: child),
    );
  }
}

/// 스티커 자리(쪽지 기준 0~1). 순서대로 붙는다.
const _stickerSlots = [(0.92, 0.0), (0.0, 0.0), (0.5, 0.0)];

/// 한마디 쓰기 시트: 200자 + 스티커 3개, 사진 없음(SPEC 6)
class JoinSheet extends ConsumerStatefulWidget {
  const JoinSheet({super.key, required this.paper});

  final RollingPaper paper;

  @override
  ConsumerState<JoinSheet> createState() => _JoinSheetState();
}

class _JoinSheetState extends ConsumerState<JoinSheet> {
  final _text = TextEditingController();
  final _stickers = <String>[];
  bool _sending = false;
  String? _error;

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  List<PlacedSticker> get _placed => [
    for (var i = 0; i < _stickers.length; i++)
      PlacedSticker(_stickers[i], _stickerSlots[i].$1, _stickerSlots[i].$2),
  ];

  Future<void> _send() async {
    final body = _text.text.trim();
    if (body.isEmpty) {
      setState(() => _error = '한 마디라도 적어 주세요.');
      return;
    }
    setState(() {
      _sending = true;
      _error = null;
    });
    try {
      await ref.read(rollingPaperProvider(widget.paper.id).notifier).join(body, _placed);
      if (mounted) Navigator.of(context).pop();
    } on ApiException catch (e) {
      if (mounted) {
        setState(() {
          _sending = false;
          _error = e.message;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final count = _text.text.characters.length;
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(16, 18, 16, 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                '${widget.paper.title}에 한마디',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.headlineSmall,
              ),
              const SizedBox(height: 4),
              const Text(
                '이름이 함께 붙어요. 두루마리마다 한 번만 남길 수 있어요.',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 12.5),
              ),
              const SizedBox(height: 14),
              LayoutBuilder(
                builder: (context, box) => Stack(
                  clipBehavior: Clip.none,
                  children: [
                    Container(
                      padding: const EdgeInsets.fromLTRB(14, 18, 14, 6),
                      decoration: BoxDecoration(
                        color: const Color(0xFFFFF4C2),
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(color: Palette.outline, width: 2),
                      ),
                      child: TextField(
                        key: const ValueKey('rolling-body'),
                        controller: _text,
                        minLines: 3,
                        maxLines: 6,
                        maxLength: 200,
                        onChanged: (_) => setState(() {}),
                        style: const TextStyle(
                          fontFamily: Fonts.handwriting,
                          fontFamilyFallback: Fonts.fallback,
                          fontSize: 21,
                          height: 1.3,
                          color: Palette.textBrown,
                        ),
                        decoration: InputDecoration(
                          border: InputBorder.none,
                          hintText: widget.paper.topic ?? '우리 동네에 전하고 싶은 한마디',
                          counterText: '$count/200',
                        ),
                      ),
                    ),
                    for (final (i, s) in _placed.indexed)
                      Positioned(
                        left: s.x * (box.maxWidth - 38),
                        top: -14,
                        child: Semantics(
                          button: true,
                          label: '${stickerLabel(s.id)} 스티커 떼기',
                          child: GestureDetector(
                            onTap: () => setState(() => _stickers.removeAt(i)),
                            child: StickerImage(s.id, size: 38),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 6),
              const Text('붙인 스티커를 누르면 떼어져요.', style: TextStyle(fontSize: 12)),
              const SizedBox(height: 8),
              StickerTray(
                full: _stickers.length >= stickersMax,
                onAdd: (id) => setState(() => _stickers.add(id)),
              ),
              if (_error != null) ...[const SizedBox(height: 10), NoticeBox(_error!)],
              const SizedBox(height: 14),
              ChunkyButton(
                key: const ValueKey('rolling-send'),
                label: '두루마리에 붙이기',
                color: Palette.yellow,
                loading: _sending,
                onPressed: _sending ? null : _send,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
