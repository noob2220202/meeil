import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api_client.dart';
import '../../core/config.dart';
import '../auth/session.dart';
import '../letters/compose_controller.dart';
import 'ad_gateway.dart';
import 'rewards_api.dart';
import 'rewards_models.dart';

/// 광고 한 번 본 결과
enum AdRewardOutcome {
  /// 포인트가 들어옴
  granted,

  /// 끝까지 봤지만 아직 서버에 확인이 안 옴(조금 뒤 들어온다)
  pending,

  /// 중간에 닫음
  dismissed,

  /// 오늘 횟수를 다 씀
  limit,

  /// 광고가 없음
  unavailable,
}

/// 출석·광고 같은 포인트 행동. 끝나면 내 정보와 업적 축하를 새로 고친다.
class RewardsActions {
  RewardsActions(
    this.ref, {
    this.pollEvery = const Duration(milliseconds: 1500),
    this.pollTimes = 8,
  });

  final Ref ref;
  final Duration pollEvery;
  final int pollTimes;

  RewardsApi get _api => ref.read(rewardsApiProvider);

  Future<void> _after() async {
    await ref.read(sessionProvider.notifier).refreshMe();
    unawaited(ref.read(unseenAchievementsProvider.notifier).poll());
  }

  /// 오늘 출석. 이미 했으면 justChecked=false
  Future<AttendanceStatus> checkIn() async {
    final s = await _api.checkIn();
    ref.invalidate(attendanceProvider);
    await _after();
    return s;
  }

  /// 보상형 광고 보기 → 서버 SSV로 들어온 포인트 확인
  Future<AdRewardOutcome> watchAd() async {
    final before = await _api.adStatus();
    if (before.remaining <= 0) return AdRewardOutcome.limit;
    final session = ref.read(sessionProvider);
    if (session is! SignedIn) return AdRewardOutcome.unavailable;
    final me = session.me;
    final shown = await ref
        .read(adGatewayProvider)
        .showRewarded(userId: me.id, underAge: me.adsUnderAge);
    if (shown == AdShowResult.failed) return AdRewardOutcome.unavailable;
    if (shown == AdShowResult.dismissed) return AdRewardOutcome.dismissed;

    var outcome = AdRewardOutcome.pending;
    if (AppConfig.devLogin) {
      // 테스트 광고는 SSV 콜백이 오지 않는다 → 개발 서버의 같은 지급 경로
      try {
        await _api.devAdReward();
      } on ApiException {
        // 운영 서버에 붙은 디버그 빌드: 콜백을 기다린다
      }
    }
    for (var i = 0; i < pollTimes; i++) {
      final now = await _api.adStatus();
      if (now.todayCount > before.todayCount) {
        outcome = AdRewardOutcome.granted;
        break;
      }
      await Future<void>.delayed(pollEvery);
    }
    ref.invalidate(adStatusProvider);
    await _after();
    return outcome;
  }

  Future<void> setTitle(String? achievementId) async {
    await _api.setTitle(achievementId);
    ref.invalidate(achievementBookProvider);
    await ref.read(sessionProvider.notifier).refreshMe();
  }
}

final rewardsActionsProvider = Provider<RewardsActions>((ref) => RewardsActions(ref));

/// 아직 축하를 못 본 업적. 메인 화면이 지켜보다가 축하 창을 띄운다.
class UnseenAchievements extends Notifier<List<Achievement>> {
  bool _busy = false;

  @override
  List<Achievement> build() => const [];

  Future<void> poll() async {
    if (_busy || state.isNotEmpty) return;
    _busy = true;
    try {
      final list = await ref.read(rewardsApiProvider).unseen();
      if (list.isNotEmpty) state = list;
    } on ApiException {
      // 다음 기회에
    } finally {
      _busy = false;
    }
  }

  /// 축하 창을 닫음 → 서버에 본 것으로 표시
  Future<void> dismiss() async {
    final ids = [for (final a in state) a.id];
    state = const [];
    if (ids.isEmpty) return;
    try {
      await ref.read(rewardsApiProvider).markSeen(ids);
    } on ApiException {
      // 다음에 다시 보여도 괜찮다
    }
    ref.invalidate(achievementBookProvider);
    ref.invalidate(stationeryProvider);
    await ref.read(sessionProvider.notifier).refreshMe();
  }
}

final unseenAchievementsProvider = NotifierProvider<UnseenAchievements, List<Achievement>>(
  UnseenAchievements.new,
);
