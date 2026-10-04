import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/theme.dart';
import '../../core/korean.dart';
import '../../ui/widgets.dart';
import '../goats/hand_availability.dart';
import '../goats/schedule.dart';
import 'letter_models.dart';
import 'letter_paper.dart';
import 'letters_api.dart';
import 'mailbox_providers.dart';

/// 상대 시각: "방금", "12분 전", "3시간 전", "10월 3일"(KST)
String formatWhen(DateTime t, DateTime now) {
  final d = now.difference(t);
  if (d.inMinutes < 1) return '방금';
  if (d.inHours < 1) return '${d.inMinutes}분 전';
  if (d.inHours < 24) return '${d.inHours}시간 전';
  final k = t.toUtc().add(const Duration(hours: 9));
  return '${k.month}월 ${k.day}일';
}

/// 편지함 탭 (SPEC 5.4): 받은 편지 / 보낸 편지 / 휴지통
class MailboxTab extends ConsumerStatefulWidget {
  const MailboxTab({super.key, this.initialBox = MailBox.inbox});

  final MailBox initialBox;

  @override
  ConsumerState<MailboxTab> createState() => _MailboxTabState();
}

class _MailboxTabState extends ConsumerState<MailboxTab> {
  late MailBox _box = widget.initialBox;

  @override
  void didUpdateWidget(MailboxTab old) {
    super.didUpdateWidget(old);
    if (old.initialBox != widget.initialBox) _box = widget.initialBox;
  }

  @override
  Widget build(BuildContext context) {
    final unread = ref.watch(unreadCountProvider).value ?? 0;
    return SafeArea(
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 12, 12, 4),
            child: Row(
              children: [
                Text('편지함', style: Theme.of(context).textTheme.headlineMedium),
                const Spacer(),
                FilledButton.icon(
                  style: FilledButton.styleFrom(
                    backgroundColor: Palette.yellow,
                    foregroundColor: Palette.textBrown,
                    side: const BorderSide(color: Palette.outline, width: 2),
                  ),
                  onPressed: () => context.push('/compose'),
                  icon: const Icon(Icons.edit_rounded, size: 18),
                  label: const Text('편지 쓰기'),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Row(
              children: [
                for (final (box, label) in [
                  (MailBox.inbox, '받은 편지'),
                  (MailBox.sent, '보낸 편지'),
                  (MailBox.trash, '휴지통'),
                ])
                  Expanded(
                    child: _BoxTab(
                      label: label,
                      badge: box == MailBox.inbox ? unread : 0,
                      selected: _box == box,
                      onTap: () => setState(() => _box = box),
                    ),
                  ),
              ],
            ),
          ),
          Expanded(
            child: _BoxList(key: ValueKey(_box), box: _box),
          ),
        ],
      ),
    );
  }
}

class _BoxTab extends StatelessWidget {
  const _BoxTab({
    required this.label,
    required this.badge,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final int badge;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Semantics(
    button: true,
    selected: selected,
    label: badge > 0 ? '$label, 안 읽은 편지 $badge통' : label,
    excludeSemantics: true,
    child: GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        margin: const EdgeInsets.symmetric(horizontal: 4),
        padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 4),
        constraints: const BoxConstraints(minHeight: 48),
        decoration: BoxDecoration(
          color: selected ? Palette.yellow : Colors.white,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: Palette.outline, width: 2),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Flexible(
              child: FittedBox(
                fit: BoxFit.scaleDown,
                child: Text(
                  label,
                  style: const TextStyle(
                    fontFamily: Fonts.title,
                    fontFamilyFallback: Fonts.fallback,
                    fontSize: 15,
                  ),
                ),
              ),
            ),
            if (badge > 0) ...[
              const SizedBox(width: 6),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 1),
                decoration: BoxDecoration(
                  color: const Color(0xFFFF8FAB),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  '$badge',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 12,
                    fontFamily: Fonts.title,
                    fontFamilyFallback: Fonts.fallback,
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    ),
  );
}

class _BoxList extends ConsumerWidget {
  const _BoxList({super.key, required this.box});

  final MailBox box;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(mailboxProvider(box));
    final controller = ref.read(mailboxProvider(box).notifier);
    return state.when(
      loading: () => const Center(child: BobbingGoat(size: 96)),
      error: (e, _) => Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const NoticeBox('편지함을 불러오지 못했어요.'),
              const SizedBox(height: 12),
              ChunkyButton(label: '다시 시도', onPressed: controller.refresh),
            ],
          ),
        ),
      ),
      data: (s) {
        if (s.letters.isEmpty) {
          return RefreshIndicator(
            onRefresh: controller.refresh,
            child: ListView(children: [_Empty(box: box)]),
          );
        }
        final now = ref.watch(clockTickProvider);
        return RefreshIndicator(
          onRefresh: () async {
            await controller.refresh();
            ref.invalidate(unreadCountProvider);
          },
          child: NotificationListener<ScrollNotification>(
            onNotification: (n) {
              if (n.metrics.extentAfter < 300) controller.loadMore();
              return false;
            },
            child: ListView.separated(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
              itemCount: s.letters.length + (s.loadingMore ? 1 : 0),
              separatorBuilder: (_, _) => const SizedBox(height: 10),
              itemBuilder: (context, i) {
                if (i >= s.letters.length) {
                  return const Center(child: CircularProgressIndicator());
                }
                final l = s.letters[i];
                return EnvelopeTile(
                  letter: l,
                  box: box,
                  now: now,
                  onTap: () => context.push('/letters/${l.id}', extra: l),
                );
              },
            ),
          ),
        );
      },
    );
  }
}

class _Empty extends StatelessWidget {
  const _Empty({required this.box});
  final MailBox box;

  @override
  Widget build(BuildContext context) {
    final (illustration, title, body) = switch (box) {
      MailBox.inbox => (Illustration.letter, '아직 받은 편지가 없어요', '먼저 편지를 보내 보면\n답장이 찾아올지도 몰라요.'),
      MailBox.sent => (Illustration.goat, '아직 보낸 편지가 없어요', '우체부 염소가 우리 동네에 오면\n편지를 맡겨 보세요.'),
      MailBox.trash => (Illustration.scroll, '휴지통이 비어 있어요', '지운 편지는 30일 동안 여기 머물러요.'),
    };
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 48, 24, 24),
      child: Column(
        children: [
          IllustrationImage(illustration, size: 130),
          const SizedBox(height: 16),
          Text(title, style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 8),
          Text(body, textAlign: TextAlign.center, style: const TextStyle(height: 1.6)),
          if (box != MailBox.trash) ...[
            const SizedBox(height: 20),
            SizedBox(
              width: 200,
              child: ChunkyButton(
                label: '편지 쓰기',
                color: Palette.yellow,
                onPressed: () => context.push('/compose'),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// 편지함 한 줄: 봉투 모양 카드
class EnvelopeTile extends StatelessWidget {
  const EnvelopeTile({
    super.key,
    required this.letter,
    required this.box,
    required this.now,
    required this.onTap,
  });

  final Letter letter;
  final MailBox box;
  final DateTime now;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final l = letter;
    final style = StationeryStyle.of(l.stationeryId);
    final title = l.isEaten
        ? '염소가 먹어버린 편지'
        : l.isSender
        ? (l.recipient == null ? '랜덤 편지 · 누군가에게' : '${l.recipient!.nickname}님에게')
        : '${l.sender.nickname}님의 편지';
    final subtitle = _subtitle();
    final when = l.isSender ? l.handedAt : (l.deliveredAt ?? l.handedAt);
    return Semantics(
      button: true,
      label: '$title. $subtitle',
      child: Material(
        color: style.paper,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(18),
          side: const BorderSide(color: Palette.outline, width: 2),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 12, 14, 12),
            child: Row(
              children: [
                _EnvelopeIcon(
                  sealed: l.isUnread,
                  eaten: l.isEaten,
                  inTransit: l.status == LetterStatus.inTransit,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Flexible(
                            child: Text(
                              title,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontFamily: Fonts.title,
                                fontFamilyFallback: Fonts.fallback,
                                fontSize: 17,
                              ),
                            ),
                          ),
                          if (l.isUnread) ...[
                            const SizedBox(width: 6),
                            const _Chip('새 편지', Color(0xFFFF8FAB), Colors.white),
                          ],
                          if (l.mode == LetterMode.random && !l.isSender) ...[
                            const SizedBox(width: 6),
                            const _Chip('랜덤', Palette.mint, Palette.textBrown),
                          ],
                        ],
                      ),
                      const SizedBox(height: 3),
                      Text(
                        subtitle,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 13.5),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Text(formatWhen(when, now), style: const TextStyle(fontSize: 12)),
              ],
            ),
          ),
        ),
      ),
    );
  }

  String _subtitle() {
    final l = letter;
    if (box == MailBox.trash) {
      final left = 30 - now.difference(l.trashedAt ?? now).inDays;
      return '휴지통 · ${left.clamp(0, 30)}일 뒤 영구 삭제';
    }
    if (l.isEaten) return '부적절한 내용이라 염소가 먹어버렸어요';
    if (l.isSender) {
      return switch (l.status) {
        LetterStatus.inTransit || LetterStatus.handed =>
          l.etaAt == null
              ? '배달 중'
              : '${iGa(l.goatName ?? '염소')} 가는 중 · 약 ${formatRemaining(l.etaAt!.difference(now))} 뒤 도착',
        _ => '도착했어요',
      };
    }
    if (l.isUnread) return '${iGa(l.goatName ?? '우체부 염소')} 가져왔어요 · 눌러서 열어 보세요';
    final firstLine = (l.body ?? '').split('\n').first;
    return firstLine.isEmpty ? '사진 편지' : firstLine;
  }
}

class _Chip extends StatelessWidget {
  const _Chip(this.text, this.bg, this.fg);
  final String text;
  final Color bg;
  final Color fg;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 1),
    decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(8)),
    child: Text(text, style: TextStyle(fontSize: 11.5, color: fg)),
  );
}

/// 봉투 아이콘: 안 읽음 = 하트 씰로 봉한 봉투, 읽음 = 열린 봉투, 이동 중 = 날아가는 봉투
class _EnvelopeIcon extends StatelessWidget {
  const _EnvelopeIcon({required this.sealed, required this.eaten, required this.inTransit});

  final bool sealed;
  final bool eaten;
  final bool inTransit;

  @override
  Widget build(BuildContext context) => SizedBox(
    width: 52,
    height: 42,
    child: eaten
        ? const StickerImage('goat-tear', size: 42)
        : CustomPaint(
            painter: _EnvelopePainter(sealed: sealed, inTransit: inTransit),
          ),
  );
}

class _EnvelopePainter extends CustomPainter {
  _EnvelopePainter({required this.sealed, required this.inTransit});

  final bool sealed;
  final bool inTransit;

  @override
  void paint(Canvas canvas, Size size) {
    final r = RRect.fromRectAndRadius(
      Rect.fromLTWH(2, 8, size.width - 4, size.height - 10),
      const Radius.circular(6),
    );
    final stroke = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.4
      ..strokeJoin = StrokeJoin.round
      ..color = Palette.outline;
    canvas.drawRRect(r, Paint()..color = const Color(0xFFFFFFFF));
    canvas.drawRRect(r, stroke);
    final top = r.top;
    final flap = Path()
      ..moveTo(r.left + 2, top + 2)
      ..lineTo(size.width / 2, sealed ? top + 16 : top - 8)
      ..lineTo(r.right - 2, top + 2);
    canvas.drawPath(flap, stroke);
    if (sealed) {
      canvas.drawCircle(
        Offset(size.width / 2, top + 16),
        6.5,
        Paint()..color = const Color(0xFFFF8FAB),
      );
      canvas.drawCircle(Offset(size.width / 2, top + 16), 6.5, stroke..strokeWidth = 1.8);
    }
    if (inTransit) {
      final speed = Paint()
        ..strokeWidth = 2
        ..strokeCap = StrokeCap.round
        ..color = Palette.outline.withValues(alpha: 0.5);
      canvas.drawLine(const Offset(0, 20), const Offset(-8, 20), speed);
      canvas.drawLine(const Offset(0, 28), const Offset(-12, 28), speed);
    }
  }

  @override
  bool shouldRepaint(_EnvelopePainter old) => old.sealed != sealed || old.inTransit != inTransit;
}
