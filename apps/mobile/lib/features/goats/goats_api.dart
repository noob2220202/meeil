import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api_client.dart';
import '../auth/session.dart';
import 'schedule.dart';

class GoatsApi {
  GoatsApi(this.client);

  final ApiClient client;

  Future<GoatSchedule> fetchSchedule({int hours = 48}) async {
    final started = DateTime.now();
    final j = await client.get('/goats/schedule', query: {'hours': hours});
    return GoatSchedule.fromJson(j, requestStarted: started, responseReceived: DateTime.now());
  }
}

final goatsApiProvider = Provider<GoatsApi>((ref) => GoatsApi(ref.watch(apiClientProvider)));

/// 염소 스케줄. 받은 범위가 6시간 남으면(또는 30분마다) 조용히 다시 받는다.
class GoatScheduleController extends AsyncNotifier<GoatSchedule> {
  Timer? _timer;

  @override
  Future<GoatSchedule> build() async {
    ref.onDispose(() => _timer?.cancel());
    final schedule = await ref.read(goatsApiProvider).fetchSchedule();
    _scheduleRefresh(schedule);
    return schedule;
  }

  void _scheduleRefresh(GoatSchedule s) {
    _timer?.cancel();
    final untilStale = s.validUntil.difference(s.serverNow()) - const Duration(hours: 6);
    final wait = untilStale < const Duration(minutes: 30)
        ? untilStale
        : const Duration(minutes: 30);
    _timer = Timer(wait.isNegative ? const Duration(minutes: 1) : wait, refreshQuietly);
  }

  /// 화면을 비우지 않고 뒤에서 갱신(실패하면 기존 값을 유지)
  Future<void> refreshQuietly() async {
    try {
      final s = await ref.read(goatsApiProvider).fetchSchedule();
      state = AsyncData(s);
      _scheduleRefresh(s);
    } catch (_) {
      _timer = Timer(const Duration(minutes: 2), refreshQuietly);
    }
  }
}

final goatScheduleProvider = AsyncNotifierProvider<GoatScheduleController, GoatSchedule>(
  GoatScheduleController.new,
);
