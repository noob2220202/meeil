import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../location/my_region.dart';
import 'goats_api.dart';
import 'schedule.dart';

/// 20초마다 바뀌는 "지금"(서버 시각). 염소 도착·출발이 화면에 반영되게 한다.
class ClockTick extends Notifier<DateTime> {
  Timer? _timer;

  DateTime _now() => ref.read(goatScheduleProvider).value?.serverNow() ?? DateTime.now();

  @override
  DateTime build() {
    ref.watch(goatScheduleProvider);
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(seconds: 20), (_) => state = _now());
    ref.onDispose(() => _timer?.cancel());
    return _now();
  }
}

final clockTickProvider = NotifierProvider<ClockTick, DateTime>(ClockTick.new);

/// 지금 편지를 맡길 수 있는지 (SPEC 3.2: 배달 염소가 내 시에 머무는 동안만)
sealed class HandAvailability {
  const HandAvailability();
}

class CanHand extends HandAvailability {
  const CanHand(this.goat, this.leavesAt, this.now);
  final GoatInfo goat;
  final DateTime leavesAt;
  final DateTime now;
}

class WaitForGoat extends HandAvailability {
  const WaitForGoat(this.next, this.now);

  /// 다음에 올 염소와 도착 시각(받아 둔 범위에 없으면 null)
  final (GoatInfo, DateTime)? next;
  final DateTime now;
}

/// 내 위치를 모른다(권한 없음·확인 중 등)
class NeedLocation extends HandAvailability {
  const NeedLocation(this.status);
  final MyRegionStatus status;
}

class ScheduleLoading extends HandAvailability {
  const ScheduleLoading();
}

HandAvailability handAvailabilityAt({
  required GoatSchedule? schedule,
  required MyRegionState my,
  required DateTime now,
}) {
  final region = my.regionCode;
  if (region == null) return NeedLocation(my.status);
  if (schedule == null) return const ScheduleLoading();
  for (final tr in schedule.tracks.values) {
    if (tr.goat.kind != GoatKind.delivery) continue;
    if (tr.at(now) case GoatStaying(:final stop) when stop.regionCode == region) {
      return CanHand(tr.goat, stop.departAt, now);
    }
  }
  return WaitForGoat(schedule.nextDeliveryTo(region, now), now);
}

final handAvailabilityProvider = Provider<HandAvailability>((ref) {
  final schedule = ref.watch(goatScheduleProvider).value;
  final my = ref.watch(myRegionProvider);
  final now = ref.watch(clockTickProvider);
  return handAvailabilityAt(schedule: schedule, my: my, now: now);
});
