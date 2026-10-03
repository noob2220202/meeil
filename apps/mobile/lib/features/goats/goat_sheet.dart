import 'dart:async';

import 'package:flutter/material.dart';

import '../../app/theme.dart';
import '../../data/regions.dart';
import '../map/goat_painter.dart';
import '../map/goat_scene.dart';
import 'goat_avatar.dart';
import 'goat_texts.dart';
import 'schedule.dart';

/// 염소 상세 시트 (SPEC 10: 이름·속도·현재 위치·다음 방문지·ETA)
Future<void> showGoatSheet(
  BuildContext context, {
  required GoatRef ref,
  required GoatSchedule? schedule,
  required RegionData data,
  DateTime Function()? clock,
}) {
  return showModalBottomSheet<void>(
    context: context,
    backgroundColor: Palette.cream,
    showDragHandle: true,
    isScrollControlled: true,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      side: BorderSide(color: Palette.outline, width: 2.5),
    ),
    builder: (_) => GoatSheet(goatRef: ref, schedule: schedule, data: data, clock: clock),
  );
}

class GoatSheet extends StatefulWidget {
  const GoatSheet({
    super.key,
    required this.goatRef,
    required this.schedule,
    required this.data,
    this.clock,
  });

  final GoatRef goatRef;
  final GoatSchedule? schedule;
  final RegionData data;
  final DateTime Function()? clock;

  @override
  State<GoatSheet> createState() => _GoatSheetState();
}

class _GoatSheetState extends State<GoatSheet> {
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) => setState(() {}));
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  DateTime get _now => widget.clock?.call() ?? widget.schedule?.serverNow() ?? DateTime.now();

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
        child: switch (widget.goatRef) {
          CityGoatRef(:final regionCode) => _city(text, regionCode),
          ScheduledGoatRef(:final goatId) => _scheduled(text, goatId),
        },
      ),
    );
  }

  Widget _city(TextTheme text, String code) {
    final region = widget.data.byCode[code];
    final look = widget.schedule?.cityGoatLook ?? RollingLooks.city;
    return _layout(
      text,
      avatar: GoatAvatar(look: look, pose: GoatPose.walk),
      name: '${region?.name ?? ''} 분홍 두루마리',
      kind: '${region?.name ?? ''} 롤링 염소',
      status: '늘 ${region?.fullName ?? '이 시'}에 머물러요',
      detail: '이 염소가 가진 두루마리는 하루에 한 장씩 새로 펼쳐져요.',
      stops: const [],
    );
  }

  Widget _scheduled(TextTheme text, String id) {
    final track = widget.schedule?.tracks[id];
    if (track == null) {
      return _layout(
        text,
        avatar: const GoatAvatar(look: RollingLooks.city),
        name: '염소를 찾지 못했어요',
        kind: '',
        status: '일정을 다시 불러온 뒤 확인해 주세요.',
        stops: const [],
      );
    }
    final now = _now;
    final moment = track.at(now);
    final g = track.goat;
    return _layout(
      text,
      avatar: GoatAvatar(
        look: g.look,
        pose: moment is GoatTraveling ? GoatPose.walk : GoatPose.idle,
      ),
      name: g.name,
      kind: goatKindLabel(g, widget.data),
      status: goatStatusLine(moment, widget.data, now),
      detail: g.kind == GoatKind.delivery
          ? '걸음 빠르기 시속 ${g.speedKmh.round()}km · 편지 가방을 메고 다녀요'
          : '걸음 빠르기 시속 ${g.speedKmh.round()}km · 두루마리를 지고 다녀요',
      stops: track.upcoming(now),
    );
  }

  Widget _layout(
    TextTheme text, {
    required Widget avatar,
    required String name,
    required String kind,
    required String status,
    String? detail,
    required List<GoatStop> stops,
  }) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Container(
              width: 112,
              height: 112,
              decoration: BoxDecoration(
                color: Palette.sky,
                shape: BoxShape.circle,
                border: Border.all(color: Palette.outline, width: 2.5),
              ),
              alignment: Alignment.center,
              child: avatar,
            ),
            const SizedBox(width: 18),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (kind.isNotEmpty)
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
                      decoration: BoxDecoration(
                        color: Palette.mint,
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: Palette.outline, width: 1.5),
                      ),
                      child: Text(kind, style: const TextStyle(fontSize: 13)),
                    ),
                  const SizedBox(height: 6),
                  FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: Alignment.centerLeft,
                    child: Text(name, maxLines: 1, style: text.headlineMedium),
                  ),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 18),
        Text(status, style: text.titleMedium?.copyWith(height: 1.4)),
        if (detail != null) ...[
          const SizedBox(height: 6),
          Text(detail, style: text.bodyMedium?.copyWith(color: Palette.textBrown)),
        ],
        if (stops.isNotEmpty) ...[
          const SizedBox(height: 18),
          Text(
            '다음에 들를 곳',
            style: text.titleSmall?.copyWith(
              fontFamily: Fonts.title,
              fontFamilyFallback: Fonts.fallback,
            ),
          ),
          const SizedBox(height: 8),
          for (final s in stops)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 5),
              child: Row(
                children: [
                  SizedBox(
                    width: 82,
                    child: Text(formatClock(s.arriveAt), style: const TextStyle(fontSize: 15)),
                  ),
                  Icon(
                    s.bySea ? Icons.directions_boat_rounded : Icons.place_rounded,
                    size: 18,
                    color: Palette.outline,
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      widget.data.byCode[s.regionCode]?.fullName ?? s.regionCode,
                      style: const TextStyle(fontSize: 15),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ],
    );
  }
}
