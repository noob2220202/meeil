import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';

import '../../app/theme.dart';
import '../../core/api_client.dart';
import '../../core/korean.dart';
import '../../data/regions.dart';
import '../../ui/widgets.dart';
import '../auth/session.dart';
import '../goats/goat_avatar.dart';
import '../goats/hand_availability.dart';
import '../goats/schedule.dart';
import '../location/my_region.dart';
import 'compose_controller.dart';
import 'handoff_overlay.dart';
import 'letter_models.dart';
import 'letter_paper.dart';
import 'letters_api.dart';
import 'mailbox_providers.dart';
import 'user_search_screen.dart';

/// 사진 고르기(테스트에서 교체)
typedef PhotoPicker = Future<String?> Function(ImageSource source);

final photoPickerProvider = Provider<PhotoPicker>(
  (ref) => (source) async {
    // 기기에서 한 번 줄여 보내고, 서버가 다시 1280px·WebP로 만든다
    final f = await ImagePicker().pickImage(
      source: source,
      maxWidth: 2048,
      maxHeight: 2048,
      imageQuality: 88,
    );
    return f?.path;
  },
);

/// 편지 쓰기 (SPEC 10). 언제든 열 수 있고, 맡기기는 염소가 내 시에 있을 때만.
class ComposeScreen extends ConsumerStatefulWidget {
  const ComposeScreen({super.key});

  @override
  ConsumerState<ComposeScreen> createState() => _ComposeScreenState();
}

class _ComposeScreenState extends ConsumerState<ComposeScreen> {
  late final TextEditingController _body;
  bool _sending = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _body = TextEditingController(text: ref.read(composeProvider).body);
  }

  @override
  void dispose() {
    _body.dispose();
    super.dispose();
  }

  ComposeController get _c => ref.read(composeProvider.notifier);

  Future<void> _pickRecipient() async {
    final p = await Navigator.of(context)
        .push<Person>(MaterialPageRoute(builder: (_) => const UserSearchScreen()));
    if (p != null) _c.setRecipient(p);
  }

  Future<void> _pickPhoto() async {
    final source = await showModalBottomSheet<ImageSource>(
      context: context,
      backgroundColor: Palette.cream,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.photo_library_rounded),
              title: const Text('앨범에서 고르기'),
              onTap: () => Navigator.pop(context, ImageSource.gallery),
            ),
            ListTile(
              leading: const Icon(Icons.photo_camera_rounded),
              title: const Text('사진 찍기'),
              onTap: () => Navigator.pop(context, ImageSource.camera),
            ),
          ],
        ),
      ),
    );
    if (source == null) return;
    final path = await ref.read(photoPickerProvider)(source);
    if (path != null) _c.setPhoto(path);
  }

  /// 맡긴 뒤 포인트 표시 갱신(실패해도 조용히)
  Future<void> _refreshPoints() async {
    try {
      final me = await ref.read(authApiProvider).me();
      ref.read(sessionProvider.notifier).update(me);
    } on ApiException {
      // 다음에 내 정보를 볼 때 맞춰진다
    }
  }

  Future<void> _hand(CanHand at) async {
    setState(() {
      _sending = true;
      _error = null;
    });
    try {
      final letter = await _c.hand();
      _body.clear();
      // 이미 맡겨졌으므로 아래 갱신이 실패해도 오류로 보이면 안 된다
      ref.invalidate(mailboxProvider(MailBox.sent));
      _refreshPoints();
      if (!mounted) return;
      setState(() => _sending = false);
      await showHandoff(context, look: at.goat.look, goatName: at.goat.name, letter: letter);
      if (!mounted) return;
      context.go('/?tab=1&box=sent');
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = handErrorMessage(e));
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final draft = ref.watch(composeProvider);
    final isReply = draft.mode == LetterMode.reply;
    return PopScope(
      onPopInvokedWithResult: (_, _) => _c.persist(),
      child: Scaffold(
        appBar: AppBar(
          backgroundColor: Colors.transparent,
          title: Text(isReply ? '답장 쓰기' : '편지 쓰기'),
          actions: [
            if (!draft.isEmpty)
              TextButton(
                onPressed: () async {
                  final ok = await showDialog<bool>(
                    context: context,
                    builder: (context) => AlertDialog(
                      title: const Text('새로 쓸까요?'),
                      content: const Text('지금 쓰던 편지가 지워져요.'),
                      actions: [
                        TextButton(
                          onPressed: () => Navigator.pop(context, false),
                          child: const Text('아니요'),
                        ),
                        TextButton(
                          onPressed: () => Navigator.pop(context, true),
                          child: const Text('새로 쓰기'),
                        ),
                      ],
                    ),
                  );
                  if (ok == true) {
                    await _c.clear();
                    _body.clear();
                  }
                },
                child: const Text('새로 쓰기'),
              ),
          ],
        ),
        body: SafeArea(
          child: Column(
            children: [
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
                  children: [
                    _RecipientCard(draft: draft, onPick: _pickRecipient),
                    const SizedBox(height: 14),
                    AspectRatio(
                      aspectRatio: 0.82,
                      child: LetterPaper(
                        stationeryId: draft.stationeryId,
                        stickers: draft.stickers,
                        onStickerMoved: _c.moveSticker,
                        onStickerRemoved: _c.removeSticker,
                        child: TextField(
                          controller: _body,
                          onChanged: _c.setBody,
                          maxLines: null,
                          expands: true,
                          textAlignVertical: TextAlignVertical.top,
                          style: letterTextStyle(StationeryStyle.of(draft.stationeryId)),
                          cursorColor: Palette.outline,
                          decoration: const InputDecoration(
                            border: InputBorder.none,
                            hintText: '마음을 담아 적어 보세요',
                            isCollapsed: true,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 6),
                    Row(
                      children: [
                        const Expanded(
                          child: Text(
                            '스티커는 끌어서 옮기고, 길게 누르면 떼어져요',
                            style: TextStyle(fontSize: 12.5),
                          ),
                        ),
                        Text(
                          '${draft.length}/$letterBodyMax',
                          style: TextStyle(
                            fontSize: 14,
                            color: draft.length > letterBodyMax
                                ? const Color(0xFFD9485F)
                                : Palette.textBrown,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 14),
                    _StationeryRow(selected: draft.stationeryId, onSelect: _c.setStationery),
                    const SizedBox(height: 14),
                    StickerTray(full: draft.stickers.length >= stickersMax, onAdd: _c.addSticker),
                    const SizedBox(height: 14),
                    _PhotoRow(
                      path: draft.photoPath,
                      onPick: _pickPhoto,
                      onRemove: () => _c.setPhoto(null),
                      random: draft.mode == LetterMode.random,
                    ),
                  ],
                ),
              ),
              _HandBar(draft: draft, sending: _sending, error: _error, onHand: _hand),
            ],
          ),
        ),
      ),
    );
  }
}

class _RecipientCard extends ConsumerWidget {
  const _RecipientCard({required this.draft, required this.onPick});

  final ComposeDraft draft;
  final VoidCallback onPick;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = ref.read(composeProvider.notifier);
    final data = ref.watch(regionDataProvider).value;
    final myRegion = ref.watch(myRegionProvider).regionCode;
    final region = myRegion == null ? null : data?.byCode[myRegion];
    final province = region == null ? null : data?.provinceByCode[region.provinceCode];

    return _Card(
      child: draft.mode == LetterMode.reply
          ? Row(
              children: [
                const Icon(Icons.reply_rounded, color: Palette.textBrown),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    '${draft.recipient?.nickname ?? ''}님에게 답장',
                    style: const TextStyle(
                      fontFamily: Fonts.title,
                      fontFamilyFallback: Fonts.fallback,
                      fontSize: 18,
                    ),
                  ),
                ),
              ],
            )
          : Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    _ModeChip(
                      label: '지정해서 보내기',
                      selected: draft.mode == LetterMode.direct,
                      onTap: () => c.setMode(LetterMode.direct),
                    ),
                    const SizedBox(width: 8),
                    _ModeChip(
                      label: '랜덤으로 보내기',
                      selected: draft.mode == LetterMode.random,
                      onTap: () => c.setMode(LetterMode.random),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                if (draft.mode == LetterMode.direct)
                  InkWell(
                    onTap: onPick,
                    borderRadius: BorderRadius.circular(12),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 6),
                      child: Row(
                        children: [
                          const Icon(Icons.person_search_rounded, color: Palette.textBrown),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              draft.recipient == null
                                  ? '닉네임으로 받는 사람 찾기'
                                  : '${draft.recipient!.nickname}님에게',
                              style: TextStyle(
                                fontFamily: draft.recipient == null ? null : Fonts.title,
                                fontFamilyFallback: Fonts.fallback,
                                fontSize: draft.recipient == null ? 15 : 18,
                              ),
                            ),
                          ),
                          Text(draft.recipient == null ? '찾기' : '바꾸기'),
                          const Icon(Icons.chevron_right_rounded),
                        ],
                      ),
                    ),
                  )
                else
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      _ScopeChip('전국', RandomScope.nation, draft.randomScope),
                      if (province != null)
                        _ScopeChip(province.shortName, RandomScope.province, draft.randomScope),
                      if (region != null)
                        _ScopeChip(region.name, RandomScope.city, draft.randomScope),
                    ],
                  ),
                if (draft.mode == LetterMode.random) ...[
                  const SizedBox(height: 8),
                  const Text('랜덤 편지를 받겠다고 한 사람 중 한 명에게 가요.', style: TextStyle(fontSize: 12.5)),
                ],
              ],
            ),
    );
  }
}

class _ModeChip extends StatelessWidget {
  const _ModeChip({required this.label, required this.selected, required this.onTap});

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Semantics(
    selected: selected,
    button: true,
    child: GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: selected ? Palette.yellow : Colors.white,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: Palette.outline, width: 2),
        ),
        child: Text(label, style: const TextStyle(fontSize: 14)),
      ),
    ),
  );
}

class _ScopeChip extends ConsumerWidget {
  const _ScopeChip(this.label, this.scope, this.current);

  final String label;
  final RandomScope scope;
  final RandomScope current;

  @override
  Widget build(BuildContext context, WidgetRef ref) => _ModeChip(
    label: label,
    selected: scope == current,
    onTap: () => ref.read(composeProvider.notifier).setScope(scope),
  );
}

class _StationeryRow extends ConsumerWidget {
  const _StationeryRow({required this.selected, required this.onSelect});

  final String selected;
  final ValueChanged<String> onSelect;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final items =
        ref.watch(stationeryProvider).value ??
        [
          for (final s in StationeryStyle.all)
            StationeryItem(s.id, s.name, '', owned: s.id == 'cream'),
        ];
    return _Card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            '편지지',
            style: TextStyle(
              fontFamily: Fonts.title,
              fontFamilyFallback: Fonts.fallback,
              fontSize: 16,
            ),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              for (final s in items)
                Padding(
                  padding: const EdgeInsets.only(right: 10),
                  child: Tooltip(
                    message: s.owned ? s.name : s.unlockHint,
                    child: Semantics(
                      button: true,
                      selected: s.id == selected,
                      label: s.owned ? '편지지 ${s.name}' : '잠긴 편지지 ${s.name}. ${s.unlockHint}',
                      child: GestureDetector(
                        onTap: s.owned
                            ? () => onSelect(s.id)
                            : () => ScaffoldMessenger.of(
                                context,
                              ).showSnackBar(SnackBar(content: Text('${s.name}: ${s.unlockHint}'))),
                        child: Column(
                          children: [
                            Container(
                              width: 58,
                              height: 70,
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(10),
                                border: Border.all(
                                  color: Palette.outline,
                                  width: s.id == selected ? 3.5 : 1.8,
                                ),
                              ),
                              clipBehavior: Clip.antiAlias,
                              child: Stack(
                                children: [
                                  Positioned.fill(
                                    child: LetterPaper(
                                      stationeryId: s.id,
                                      child: const SizedBox.shrink(),
                                    ),
                                  ),
                                  if (!s.owned)
                                    const Positioned.fill(
                                      child: ColoredBox(
                                        color: Color(0x99FFFFFF),
                                        child: Icon(Icons.lock_rounded, color: Palette.outline),
                                      ),
                                    ),
                                ],
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(s.name, style: const TextStyle(fontSize: 12)),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

/// 스티커 고르기 줄(편지 쓰기·롤링 한마디 공용)
class StickerTray extends StatelessWidget {
  const StickerTray({super.key, required this.full, required this.onAdd});

  final bool full;
  final ValueChanged<String> onAdd;

  @override
  Widget build(BuildContext context) => _Card(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Text(
              '스티커',
              style: TextStyle(
                fontFamily: Fonts.title,
                fontFamilyFallback: Fonts.fallback,
                fontSize: 16,
              ),
            ),
            const SizedBox(width: 8),
            Text(
              full ? '세 개까지 붙일 수 있어요' : '눌러서 붙이기 (최대 $stickersMax개)',
              style: const TextStyle(fontSize: 12.5),
            ),
          ],
        ),
        const SizedBox(height: 8),
        SizedBox(
          height: 52,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: stickerIds.length,
            separatorBuilder: (_, _) => const SizedBox(width: 6),
            itemBuilder: (context, i) => Semantics(
              button: true,
              label: '${stickerLabel(stickerIds[i])} 스티커 붙이기',
              child: GestureDetector(
                onTap: full ? null : () => onAdd(stickerIds[i]),
                child: Opacity(
                  opacity: full ? 0.35 : 1,
                  child: StickerImage(stickerIds[i], size: 48),
                ),
              ),
            ),
          ),
        ),
      ],
    ),
  );
}

class _PhotoRow extends StatelessWidget {
  const _PhotoRow({
    required this.path,
    required this.onPick,
    required this.onRemove,
    required this.random,
  });

  final String? path;
  final VoidCallback onPick;
  final VoidCallback onRemove;
  final bool random;

  @override
  Widget build(BuildContext context) {
    final p = path;
    return _Card(
      child: Row(
        children: [
          if (p != null && File(p).existsSync())
            ClipRRect(
              borderRadius: BorderRadius.circular(10),
              child: Image.file(File(p), width: 64, height: 64, fit: BoxFit.cover),
            )
          else
            Container(
              width: 64,
              height: 64,
              decoration: BoxDecoration(
                color: Palette.sky,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: Palette.outline, width: 1.8),
              ),
              child: const Icon(Icons.add_a_photo_rounded, color: Palette.textBrown),
            ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  '사진 한 장',
                  style: TextStyle(
                    fontFamily: Fonts.title,
                    fontFamilyFallback: Fonts.fallback,
                    fontSize: 16,
                  ),
                ),
                Text(
                  random ? '랜덤 편지 사진은 받는 사람이 눌러야 보여요' : '위치 정보는 지우고 보내요',
                  style: const TextStyle(fontSize: 12.5),
                ),
              ],
            ),
          ),
          if (p != null)
            TextButton(onPressed: onRemove, child: const Text('빼기'))
          else
            TextButton(onPressed: onPick, child: const Text('고르기')),
        ],
      ),
    );
  }
}

/// 아래 맡기기 영역: 염소가 왔을 때만 버튼이 켜진다
class _HandBar extends ConsumerWidget {
  const _HandBar({
    required this.draft,
    required this.sending,
    required this.error,
    required this.onHand,
  });

  final ComposeDraft draft;
  final bool sending;
  final String? error;
  final void Function(CanHand) onHand;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final availability = ref.watch(handAvailabilityProvider);
    final session = ref.watch(sessionProvider);
    final points = session is SignedIn ? session.me.pointsBalance : null;

    final (Widget? avatar, String note) = switch (availability) {
      CanHand(:final goat, :final leavesAt, :final now) => (
        GoatAvatar(look: goat.look, size: 46),
        '${iGa(goat.name)} 우리 동네에 있어요 · ${formatRemaining(leavesAt.difference(now))} 뒤 떠나요',
      ),
      WaitForGoat(next: (final g, final at), :final now) => (
        GoatAvatar(look: g.look, size: 46),
        '다음 염소 ${g.name} · ${formatRemaining(at.difference(now))} 뒤 (${formatClock(at)}). 쓰던 편지는 저장돼요.',
      ),
      WaitForGoat() => (null, '곧 염소가 들를 거예요. 쓰던 편지는 저장돼요.'),
      NeedLocation() => (null, '위치를 켜면 염소가 왔을 때 맡길 수 있어요.'),
      ScheduleLoading() => (null, '염소 일정을 불러오는 중…'),
    };

    final missing = !draft.hasRecipient
        ? '받는 사람을 골라 주세요'
        : draft.length == 0
        ? '편지를 적어 주세요'
        : draft.length > letterBodyMax
        ? '$letterBodyMax자를 넘었어요'
        : null;

    return Container(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(top: BorderSide(color: Palette.outline, width: 2)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (error != null) ...[NoticeBox(error!), const SizedBox(height: 10)],
          Row(
            children: [
              ?avatar,
              if (avatar != null) const SizedBox(width: 8),
              Expanded(child: Text(note, style: const TextStyle(fontSize: 13.5, height: 1.35))),
              if (points != null)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: Palette.yellow,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(
                    '${points}P',
                    style: const TextStyle(
                      fontFamily: Fonts.title,
                      fontFamilyFallback: Fonts.fallback,
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 10),
          ChunkyButton(
            label: switch (availability) {
              CanHand(:final goat) => missing ?? '${goat.name}에게 맡기기 · 1P',
              _ => '염소를 기다리는 중',
            },
            color: Palette.yellow,
            loading: sending,
            onPressed: availability is CanHand && missing == null
                ? () => onHand(availability)
                : null,
          ),
        ],
      ),
    );
  }
}

class _Card extends StatelessWidget {
  const _Card({required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) => Container(
    width: double.infinity,
    padding: const EdgeInsets.all(14),
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(18),
      border: Border.all(color: Palette.outline, width: 2),
    ),
    child: child,
  );
}
