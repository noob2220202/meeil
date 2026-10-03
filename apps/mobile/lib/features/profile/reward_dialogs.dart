import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/theme.dart';
import '../../core/api_client.dart';
import '../../core/sound.dart';
import '../../ui/widgets.dart';
import '../rewards/rewards_api.dart';
import '../rewards/rewards_controller.dart';
import '../rewards/rewards_models.dart';

/// 출석하고 "+3P" 축하. 이미 했으면 조용히 넘어간다.
Future<void> checkInWithCelebration(BuildContext context, WidgetRef ref) async {
  try {
    final s = await ref.read(rewardsActionsProvider).checkIn();
    if (!context.mounted || !s.justChecked) return;
    playSfxIn(context, Sfx.stamp);
    final bonus = s.earned > s.dailyPoints;
    await showRewardDialog(
      context,
      key: const ValueKey('attendance-dialog'),
      headline: '+${s.earned}P',
      title: bonus ? '${s.streak}일 연속 출석!' : '출석 완료!',
      body: bonus
          ? '연속 보너스 ${s.streakBonus}P까지 받았어요.'
          : '${s.streak}일째 연속이에요. ${s.daysToStreakBonus}일 더 오면 보너스 ${s.streakBonus}P!',
    );
  } on ApiException catch (e) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
    }
  }
}

/// 광고 보고 결과 안내
Future<void> watchAdWithFeedback(BuildContext context, WidgetRef ref) async {
  final messenger = ScaffoldMessenger.of(context);
  AdRewardOutcome outcome;
  try {
    outcome = await ref.read(rewardsActionsProvider).watchAd();
  } on ApiException catch (e) {
    messenger.showSnackBar(SnackBar(content: Text(e.message)));
    return;
  }
  if (!context.mounted) return;
  switch (outcome) {
    case AdRewardOutcome.granted:
      playSfxIn(context, Sfx.points);
      await showRewardDialog(
        context,
        key: const ValueKey('ad-dialog'),
        headline: '+${ref.read(adStatusProvider).value?.rewardPoints ?? 2}P',
        title: '고마워요!',
        body: '염소가 풀을 맛있게 먹었어요.',
      );
    case AdRewardOutcome.pending:
      messenger.showSnackBar(const SnackBar(content: Text('포인트를 확인하고 있어요. 잠시 뒤 들어와요.')));
    case AdRewardOutcome.dismissed:
      messenger.showSnackBar(const SnackBar(content: Text('광고를 끝까지 보면 포인트를 받아요.')));
    case AdRewardOutcome.limit:
      messenger.showSnackBar(const SnackBar(content: Text('오늘은 광고를 다 봤어요. 내일 또 만나요!')));
    case AdRewardOutcome.unavailable:
      messenger.showSnackBar(const SnackBar(content: Text('지금은 볼 수 있는 광고가 없어요. 조금 뒤에 다시 해 주세요.')));
  }
}

Future<void> showRewardDialog(
  BuildContext context, {
  Key? key,
  required String headline,
  required String title,
  required String body,
}) => showDialog<void>(
  context: context,
  builder: (context) => _CelebrationDialog(key: key, headline: headline, title: title, body: body),
);

/// 업적 달성 축하. 여러 개면 한 장에 모아 보여 준다.
Future<void> showAchievementCelebration(BuildContext context, List<Achievement> list) {
  final first = list.first;
  final rewards = <String>[
    for (final a in list) ...[
      if (a.rewardPoints > 0) '+${a.rewardPoints}P',
      if (a.titleText != null) '칭호 「${a.titleText}」',
      if (a.stationeryName != null) '편지지 「${a.stationeryName}」',
    ],
  ];
  playSfxIn(context, Sfx.points);
  return showDialog<void>(
    context: context,
    builder: (context) => _CelebrationDialog(
      key: const ValueKey('achievement-dialog'),
      headline: '업적 달성!',
      title: list.length == 1 ? first.name : '${first.name} 외 ${list.length - 1}개',
      body: list.length == 1 ? first.description : [for (final a in list) a.name].join(' · '),
      chips: rewards,
    ),
  );
}

class _CelebrationDialog extends StatelessWidget {
  const _CelebrationDialog({
    super.key,
    required this.headline,
    required this.title,
    required this.body,
    this.chips = const [],
  });

  final String headline;
  final String title;
  final String body;
  final List<String> chips;

  @override
  Widget build(BuildContext context) => Dialog(
    backgroundColor: Palette.cream,
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(28),
      side: const BorderSide(color: Palette.outline, width: 2.5),
    ),
    child: Padding(
      padding: const EdgeInsets.fromLTRB(22, 18, 22, 18),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            height: 130,
            child: Stack(
              alignment: Alignment.center,
              children: [
                const Positioned.fill(child: CustomPaint(painter: _BurstPainter())),
                const BobbingGoat(size: 104),
              ],
            ),
          ),
          Text(
            headline,
            style: const TextStyle(
              fontFamily: Fonts.title,
              fontFamilyFallback: Fonts.fallback,
              fontSize: 30,
              color: Color(0xFFE08A5C),
            ),
          ),
          const SizedBox(height: 4),
          Text(
            title,
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontFamily: Fonts.title,
              fontFamilyFallback: Fonts.fallback,
              fontSize: 21,
              color: Palette.textBrown,
            ),
          ),
          const SizedBox(height: 6),
          Text(body, textAlign: TextAlign.center, style: const TextStyle(height: 1.5)),
          if (chips.isNotEmpty) ...[
            const SizedBox(height: 12),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              alignment: WrapAlignment.center,
              children: [
                for (final c in chips)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: Palette.yellow,
                      borderRadius: BorderRadius.circular(99),
                      border: Border.all(color: Palette.outline, width: 1.5),
                    ),
                    child: Text(c, style: const TextStyle(fontSize: 13)),
                  ),
              ],
            ),
          ],
          const SizedBox(height: 16),
          ChunkyButton(
            label: '좋아요!',
            color: Palette.yellow,
            onPressed: () => Navigator.of(context).pop(),
          ),
        ],
      ),
    ),
  );
}

/// 뒤에서 퍼지는 햇살
class _BurstPainter extends CustomPainter {
  const _BurstPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final c = size.center(Offset.zero);
    final r = size.shortestSide * 0.62;
    final rays = Paint()..color = const Color(0x55FFE08A);
    for (var i = 0; i < 12; i++) {
      final a = i * math.pi / 6;
      final path = Path()
        ..moveTo(c.dx, c.dy)
        ..lineTo(c.dx + r * math.cos(a - 0.13), c.dy + r * math.sin(a - 0.13))
        ..lineTo(c.dx + r * math.cos(a + 0.13), c.dy + r * math.sin(a + 0.13))
        ..close();
      canvas.drawPath(path, rays);
    }
    final dot = Paint()..color = const Color(0xFFFFC9D6);
    for (final (dx, dy) in [(-0.8, -0.5), (0.85, -0.35), (-0.6, 0.7), (0.7, 0.65)]) {
      canvas.drawCircle(c.translate(dx * r, dy * r * 0.8), 5, dot);
    }
  }

  @override
  bool shouldRepaint(_BurstPainter old) => false;
}
