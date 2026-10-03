import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/theme.dart';
import '../../core/api_client.dart';
import '../../core/korean.dart';
import '../../data/regions.dart';
import '../../ui/widgets.dart';
import '../goats/goats_api.dart';
import '../goats/hand_availability.dart';
import '../goats/schedule.dart';
import '../map/goat_painter.dart';
import '../safety/goat_eating.dart';
import '../safety/report_sheet.dart';
import '../safety/safety_api.dart';
import 'compose_controller.dart';
import 'letter_models.dart';
import 'letter_paper.dart';
import 'letters_api.dart';
import 'mailbox_providers.dart';

final letterProvider = FutureProvider.autoDispose.family<Letter, String>(
  (ref, id) => ref.watch(lettersApiProvider).get(id),
);

/// 편지 읽기 (SPEC 10: 편지 상세/답장, 도착 연출)
class LetterScreen extends ConsumerStatefulWidget {
  const LetterScreen({super.key, required this.id, this.initial});

  final String id;

  /// 편지함에서 넘겨받은 값(먼저 그려 두고 서버 값으로 갱신)
  final Letter? initial;

  @override
  ConsumerState<LetterScreen> createState() => _LetterScreenState();
}

class _LetterScreenState extends ConsumerState<LetterScreen> {
  bool _arrivalDone = false;
  bool _photoRevealed = false;
  bool _busy = false;

  /// 읽음 표시 후 서버가 돌려준 편지
  Letter? _read;

  @override
  void initState() {
    super.initState();
    // 안 읽은 받은 편지는 도착 연출부터
    _arrivalDone = !(widget.initial?.isUnread ?? false);
  }

  bool _markingRead = false;

  Future<void> _markRead(Letter l) async {
    if (!l.isUnread || _markingRead) return;
    _markingRead = true;
    try {
      final read = await ref.read(lettersApiProvider).markRead(l.id);
      if (!mounted) return;
      setState(() => _read = read);
      ref.read(mailboxProvider(MailBox.inbox).notifier).replace(read);
      ref.invalidate(unreadCountProvider);
    } on ApiException {
      // 읽음 표시 실패는 조용히 넘어간다(다음에 다시 열면 된다)
    }
  }

  Future<void> _act(Future<Letter?> Function() action, {required String done}) async {
    setState(() => _busy = true);
    try {
      await action();
      refreshMailboxesFromWidget(ref);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(done)));
      context.pop();
    } on ApiException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<bool> _confirm(String title, String body, String ok) async =>
      await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text(title),
          content: Text(body),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('취소')),
            TextButton(onPressed: () => Navigator.pop(context, true), child: Text(ok)),
          ],
        ),
      ) ??
      false;

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(letterProvider(widget.id));
    // 읽음 처리 후 받은 값 > 서버에서 새로 받은 값 > 편지함에서 넘겨받은 값
    final letter = _read ?? async.value ?? widget.initial;

    if (letter == null) {
      return Scaffold(
        appBar: AppBar(backgroundColor: Colors.transparent),
        body: Center(
          child: async.hasError
              ? Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      NoticeBox(
                        async.error is ApiException
                            ? (async.error! as ApiException).message
                            : '편지를 열지 못했어요.',
                      ),
                      const SizedBox(height: 12),
                      ChunkyButton(
                        label: '다시 시도',
                        onPressed: () => ref.invalidate(letterProvider(widget.id)),
                      ),
                    ],
                  ),
                )
              : const BobbingGoat(size: 100),
        ),
      );
    }

    if (!_arrivalDone && letter.isUnread) {
      return ArrivalScene(
        letter: letter,
        onDone: () {
          setState(() => _arrivalDone = true);
          _markRead(letter);
        },
      );
    }
    if (letter.isUnread && _arrivalDone) {
      // 연출을 건너뛰고 들어온 경우
      Future.microtask(() => _markRead(letter));
    }

    final current = letter;
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        title: Text(
          current.isSender
              ? (current.recipient == null ? '보낸 랜덤 편지' : '${current.recipient!.nickname}님에게 보낸 편지')
              : '${current.sender.nickname}님의 편지',
        ),
        actions: [
          // 받은 편지: 신고·차단 (SPEC 9.1)
          if (!current.isSender && !current.isEaten)
            IconButton(
              key: const ValueKey('letter-more'),
              tooltip: '신고·차단',
              icon: const Icon(Icons.more_vert_rounded),
              onPressed: () => showSafetyMenu(
                context,
                target: ReportTarget.letter,
                targetId: current.id,
                userId: current.sender.id,
                nickname: current.sender.nickname,
                onBlocked: () {
                  refreshMailboxesFromWidget(ref);
                  if (context.mounted) context.pop();
                },
              ),
            ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 20),
                children: [
                  if (current.isEaten)
                    EatenLetterCard(letter: current)
                  else
                    AspectRatio(
                      aspectRatio: 0.82,
                      child: LetterPaper(
                        stationeryId: current.stationeryId,
                        stickers: current.stickers,
                        child: _LetterText(letter: current),
                      ),
                    ),
                  if (current.photo != null) ...[
                    const SizedBox(height: 14),
                    _Photo(
                      photo: current.photo!,
                      revealed: _photoRevealed || !current.photo!.blurred,
                      onReveal: () => setState(() => _photoRevealed = true),
                    ),
                  ],
                  const SizedBox(height: 16),
                  if (current.isSender)
                    _Journey(letter: current)
                  else
                    _ReceivedMeta(letter: current),
                ],
              ),
            ),
            _Actions(
              letter: current,
              busy: _busy,
              onReply: () {
                ref.read(composeProvider.notifier).startReply(current.id, current.sender);
                context.push('/compose');
              },
              onTrash: () => _act(
                () => ref.read(lettersApiProvider).trash(current.id),
                done: '휴지통으로 옮겼어요. 30일 안에는 되살릴 수 있어요.',
              ),
              onRestore: () =>
                  _act(() => ref.read(lettersApiProvider).restore(current.id), done: '편지를 되살렸어요.'),
              onPurge: () async {
                if (await _confirm('영구 삭제', '내 편지함에서 완전히 지워져요. 상대방 편지는 그대로예요.', '지우기')) {
                  await _act(() async {
                    await ref.read(lettersApiProvider).purge(current.id);
                    return null;
                  }, done: '편지를 완전히 지웠어요.');
                }
              },
            ),
          ],
        ),
      ),
    );
  }
}

class _LetterText extends StatelessWidget {
  const _LetterText({required this.letter});
  final Letter letter;

  @override
  Widget build(BuildContext context) {
    final style = letterTextStyle(StationeryStyle.of(letter.stationeryId));
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(
          child: SingleChildScrollView(child: SelectableText(letter.body ?? '', style: style)),
        ),
        Align(
          alignment: Alignment.bottomRight,
          child: Text.rich(
            TextSpan(
              children: [
                TextSpan(text: '— ${letter.sender.nickname}', style: style),
                if (letter.sender.title != null)
                  TextSpan(
                    text: '  ${letter.sender.title}',
                    style: style.copyWith(fontSize: 14, color: style.color?.withValues(alpha: 0.7)),
                  ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _Photo extends StatelessWidget {
  const _Photo({required this.photo, required this.revealed, required this.onReveal});

  final LetterPhoto photo;
  final bool revealed;
  final VoidCallback onReveal;

  @override
  Widget build(BuildContext context) {
    final image = Image.network(
      photo.url,
      fit: BoxFit.cover,
      loadingBuilder: (context, child, progress) => progress == null
          ? child
          : const ColoredBox(
              color: Palette.sky,
              child: Center(child: CircularProgressIndicator()),
            ),
      errorBuilder: (context, _, _) => const ColoredBox(
        color: Palette.pink,
        child: Center(child: Text('사진을 불러오지 못했어요')),
      ),
    );
    return AspectRatio(
      aspectRatio: photo.width / photo.height,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(18),
        child: Stack(
          fit: StackFit.expand,
          children: [
            if (revealed)
              image
            else
              ImageFiltered(imageFilter: ui.ImageFilter.blur(sigmaX: 22, sigmaY: 22), child: image),
            if (!revealed)
              Semantics(
                button: true,
                label: '가려진 사진 보기',
                child: GestureDetector(
                  onTap: onReveal,
                  child: const ColoredBox(
                    color: Color(0x55FFF8EC),
                    child: Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.visibility_rounded, color: Palette.textBrown, size: 30),
                          SizedBox(height: 6),
                          Text('랜덤 편지 사진이에요 · 눌러서 보기'),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            const IgnorePointer(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  border: Border.fromBorderSide(BorderSide(color: Palette.outline, width: 2.5)),
                  borderRadius: BorderRadius.all(Radius.circular(18)),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ReceivedMeta extends ConsumerWidget {
  const _ReceivedMeta({required this.letter});
  final Letter letter;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final data = ref.watch(regionDataProvider).value;
    final from = data?.byCode[letter.originRegionCode]?.fullName;
    final at = letter.deliveredAt;
    return Text(
      [
        if (at != null) '${formatClock(at)}에 ${iGa(letter.goatName ?? '우체부 염소')} 가져왔어요',
        if (from != null) '$from에서 보낸 편지',
      ].join('\n'),
      style: const TextStyle(fontSize: 13.5, height: 1.6),
    );
  }
}

/// 보낸 편지의 여정: 맡김 → 이동 중 → 도착
class _Journey extends ConsumerWidget {
  const _Journey({required this.letter});
  final Letter letter;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final data = ref.watch(regionDataProvider).value;
    String place(String? code) => code == null ? '' : (data?.byCode[code]?.fullName ?? '');
    final delivered = letter.deliveredAt != null;
    final now = ref.watch(clockTickProvider);
    String at(DateTime t, String? code) =>
        [formatClock(t), place(code)].where((s) => s.isNotEmpty).join(' · ');
    final eatenOnWay = letter.isEaten && !delivered;
    final steps = eatenOnWay
        ? [
            ('맡김', at(letter.handedAt, letter.originRegionCode), true),
            ('${iGa(letter.goatName ?? '염소')} 먹어버렸어요', '배달하던 길에 · 부적절한 내용', true),
          ]
        : [
            ('맡김', at(letter.handedAt, letter.originRegionCode), true),
            (
              letter.express ? '특급 배달 중' : '배달 중',
              letter.etaAt == null
                  ? ''
                  : delivered
                  ? '${iGa(letter.goatName ?? '염소')} 들고 갔어요'
                  : '${iGa(letter.goatName ?? '염소')} 가는 중 · 약 ${formatRemaining(letter.etaAt!.difference(now))} 뒤',
              true,
            ),
            (
              '도착',
              delivered
                  ? at(letter.deliveredAt!, letter.destRegionCode)
                  : letter.etaAt == null
                  ? ''
                  : '${formatClock(letter.etaAt!)} 도착 예정${place(letter.destRegionCode).isEmpty ? '' : ' · ${place(letter.destRegionCode)}'}',
              delivered,
            ),
          ];
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Palette.outline, width: 2),
      ),
      child: Column(
        children: [
          for (final (i, (title, sub, done)) in steps.indexed)
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Column(
                  children: [
                    Icon(
                      done ? Icons.check_circle_rounded : Icons.radio_button_unchecked_rounded,
                      color: done ? const Color(0xFF2E8B57) : Palette.outline,
                      size: 22,
                    ),
                    if (i < steps.length - 1)
                      Container(
                        width: 2,
                        height: 22,
                        color: Palette.outline.withValues(alpha: 0.4),
                      ),
                  ],
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: const TextStyle(
                          fontFamily: Fonts.title,
                          fontFamilyFallback: Fonts.fallback,
                          fontSize: 16,
                        ),
                      ),
                      if (sub.isNotEmpty) Text(sub, style: const TextStyle(fontSize: 13)),
                    ],
                  ),
                ),
              ],
            ),
        ],
      ),
    );
  }
}

class _Actions extends StatelessWidget {
  const _Actions({
    required this.letter,
    required this.busy,
    required this.onReply,
    required this.onTrash,
    required this.onRestore,
    required this.onPurge,
  });

  final Letter letter;
  final bool busy;
  final VoidCallback onReply;
  final VoidCallback onTrash;
  final VoidCallback onRestore;
  final VoidCallback onPurge;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(top: BorderSide(color: Palette.outline, width: 2)),
      ),
      child: letter.inTrash
          ? Row(
              children: [
                Expanded(
                  child: ChunkyButton(label: '되살리기', onPressed: busy ? null : onRestore),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: ChunkyButton(
                    label: '영구 삭제',
                    color: Palette.pink,
                    onPressed: busy ? null : onPurge,
                  ),
                ),
              ],
            )
          : Row(
              children: [
                if (letter.canReply) ...[
                  Expanded(
                    flex: 2,
                    child: ChunkyButton(
                      label: '답장 쓰기',
                      color: Palette.yellow,
                      onPressed: busy ? null : onReply,
                    ),
                  ),
                  const SizedBox(width: 10),
                ],
                Expanded(
                  child: ChunkyButton(
                    label: '휴지통',
                    color: Colors.white,
                    loading: busy,
                    onPressed: letter.status == LetterStatus.inTransit ? null : onTrash,
                  ),
                ),
              ],
            ),
    );
  }
}

/// 염소가 먹어버린 편지 자리(SPEC 9.3). 먹는 연출은 M6.
/// 염소가 먹어버린 편지 (SPEC 9.3): 먹는 연출 + 안내
class EatenLetterCard extends StatelessWidget {
  const EatenLetterCard({super.key, required this.letter, this.frozenAt});

  final Letter letter;

  @visibleForTesting
  final double? frozenAt;

  @override
  Widget build(BuildContext context) {
    final goat = letter.goatName ?? '우체부 염소';
    final wasDelivered = letter.deliveredAt != null;
    return Container(
      key: const ValueKey('eaten-letter'),
      padding: const EdgeInsets.fromLTRB(16, 20, 16, 24),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Palette.outline, width: 2.5),
      ),
      child: Column(
        children: [
          GoatEatingScene(look: letter.goatLook ?? RollingLooks.city, frozenAt: frozenAt),
          const SizedBox(height: 12),
          Text(
            letter.isSender && !wasDelivered ? '${iGa(goat)} 편지를 먹어버렸어요' : '염소가 먹어버린 편지',
            style: const TextStyle(
              fontFamily: Fonts.title,
              fontFamilyFallback: Fonts.fallback,
              fontSize: 20,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            letter.isSender
                ? (wasDelivered
                      ? '부적절한 내용이 있어서 ${letter.recipient?.nickname ?? '받는 사람'}님 편지함에서 염소가 꿀꺽 먹어버렸어요.'
                      : '부적절한 내용이 있어서 ${letter.recipient?.nickname ?? '받는 사람'}님에게 가는 길에 꿀꺽 먹어버렸어요. 편지는 전해지지 않아요.')
                : '부적절한 내용이 있어서 우체부 염소가 꿀꺽 먹어버렸어요.',
            textAlign: TextAlign.center,
            style: const TextStyle(height: 1.5),
          ),
        ],
      ),
    );
  }
}

/// 편지 도착 연출: 염소가 봉투를 물고 뒤뚱뒤뚱 와서 내려놓고, 봉투가 열린다. 탭하면 건너뛴다.
class ArrivalScene extends StatefulWidget {
  const ArrivalScene({super.key, required this.letter, required this.onDone, this.frozenAt});

  final Letter letter;
  final VoidCallback onDone;

  /// 스크린샷용: 이 진행도(0~1)에서 멈춘다
  @visibleForTesting
  final double? frozenAt;

  @override
  State<ArrivalScene> createState() => _ArrivalSceneState();
}

class _ArrivalSceneState extends State<ArrivalScene> with SingleTickerProviderStateMixin {
  late final _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 2800))
    ..addStatusListener((s) {
      if (s == AnimationStatus.completed) widget.onDone();
    });

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (widget.frozenAt != null) {
      _c.value = widget.frozenAt!;
    } else if (MediaQuery.disableAnimationsOf(context)) {
      WidgetsBinding.instance.addPostFrameCallback((_) => widget.onDone());
    } else if (!_c.isAnimating && _c.value == 0) {
      _c.forward();
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Consumer(
      builder: (context, ref, _) {
        final look =
            widget.letter.goatLook ??
            ref.watch(goatScheduleProvider).value?.tracks[widget.letter.goatId]?.goat.look ??
            RollingLooks.city;
        return Scaffold(
          backgroundColor: Palette.sky,
          body: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: widget.onDone,
            child: SafeArea(
              child: Column(
                children: [
                  const Spacer(),
                  SizedBox(
                    height: 260,
                    child: AnimatedBuilder(
                      animation: _c,
                      builder: (context, _) => CustomPaint(
                        size: Size.infinite,
                        painter: _ArrivalPainter(_c.value, look),
                      ),
                    ),
                  ),
                  const SizedBox(height: 20),
                  Text('편지가 도착했어요!', style: Theme.of(context).textTheme.headlineMedium),
                  const SizedBox(height: 8),
                  Text(
                    '${iGa(widget.letter.goatName ?? '우체부 염소')} ${widget.letter.sender.nickname}님의 편지를 가져왔어요',
                    textAlign: TextAlign.center,
                  ),
                  const Spacer(),
                  const Padding(
                    padding: EdgeInsets.only(bottom: 24),
                    child: Text('화면을 누르면 바로 열어요', style: TextStyle(fontSize: 12)),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

class _ArrivalPainter extends CustomPainter {
  _ArrivalPainter(this.p, this.look);

  final double p;
  final GoatLook look;

  @override
  void paint(Canvas canvas, Size size) {
    final ground = size.height * 0.92;
    final cx = size.width / 2;
    // 0~0.45 왼쪽에서 걸어 들어옴, 0.45~0.6 봉투 내려놓기, 0.6~1 봉투가 열리고 하트
    final walk = Curves.easeOut.transform((p / 0.45).clamp(0.0, 1.0));
    final goatX = -80 + (cx - 40 + 80) * walk;
    final walking = p < 0.45;
    GoatPainterKit.paint(
      canvas,
      at: Offset(goatX, ground),
      size: 140,
      look: look,
      t: p * 2.8,
      pose: walking ? GoatPose.walk : GoatPose.idle,
    );

    // 봉투: 처음엔 염소 입가에, 이후 앞에 떨어져 통통
    final drop = ((p - 0.45) / 0.15).clamp(0.0, 1.0);
    final mouth = Offset(goatX + 30, ground - 70);
    final landed = Offset(cx + 70, ground - 20);
    final bounce = drop >= 1 ? -10 * math.sin(((p - 0.6) / 0.12).clamp(0.0, 1.0) * math.pi) : 0.0;
    final pos = Offset.lerp(mouth, landed, Curves.easeIn.transform(drop))! + Offset(0, bounce);
    final open = ((p - 0.66) / 0.2).clamp(0.0, 1.0);
    _envelope(canvas, pos, 1 + 0.5 * drop, open);

    if (open > 0) {
      final heart = Paint()..color = const Color(0xFFFF8FAB).withValues(alpha: 1 - open * 0.6);
      for (var i = 0; i < 3; i++) {
        final a = -math.pi / 2 + (i - 1) * 0.5;
        final r = 20 + 50 * open;
        _heart(canvas, pos + Offset(math.cos(a) * r, math.sin(a) * r - 10), 7 + i * 1.5, heart);
      }
    }
  }

  void _envelope(Canvas canvas, Offset c, double s, double open) {
    canvas.save();
    canvas.translate(c.dx, c.dy);
    canvas.scale(s);
    final body = RRect.fromRectAndRadius(
      Rect.fromCenter(center: Offset.zero, width: 56, height: 38),
      const Radius.circular(6),
    );
    final stroke = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3
      ..strokeJoin = StrokeJoin.round
      ..color = Palette.outline;
    if (open > 0) {
      // 안에서 편지지가 올라온다
      final paper = Rect.fromCenter(center: Offset(0, -22 * open), width: 44, height: 34);
      canvas.drawRect(paper, Paint()..color = const Color(0xFFFFF8EC));
      canvas.drawRect(paper, stroke);
    }
    canvas.drawRRect(body, Paint()..color = const Color(0xFFFFFFFF));
    canvas.drawRRect(body, stroke);
    final flapTip = Offset(0, -19 + 36 * (1 - open) - 34 * open);
    canvas.drawPath(
      Path()
        ..moveTo(-26, -17)
        ..lineTo(flapTip.dx, flapTip.dy * (open > 0 ? 1 : 0.1) + (open > 0 ? 0 : 2))
        ..lineTo(26, -17),
      stroke,
    );
    if (open == 0) {
      canvas.drawCircle(const Offset(0, 2), 6, Paint()..color = const Color(0xFFFF8FAB));
    }
    canvas.restore();
  }

  void _heart(Canvas canvas, Offset c, double r, Paint paint) {
    canvas.drawPath(
      Path()
        ..moveTo(c.dx, c.dy + r)
        ..cubicTo(
          c.dx - r * 1.6,
          c.dy - r * 0.1,
          c.dx - r * 0.9,
          c.dy - r * 1.35,
          c.dx,
          c.dy - r * 0.45,
        )
        ..cubicTo(c.dx + r * 0.9, c.dy - r * 1.35, c.dx + r * 1.6, c.dy - r * 0.1, c.dx, c.dy + r),
      paint,
    );
  }

  @override
  bool shouldRepaint(_ArrivalPainter old) => old.p != p;
}
