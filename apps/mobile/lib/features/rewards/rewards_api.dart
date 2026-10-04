import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api_client.dart';
import '../auth/session.dart';
import 'rewards_models.dart';

class RewardsApi {
  RewardsApi(this.client);

  final ApiClient client;

  Future<AttendanceStatus> attendance({String? month}) async =>
      AttendanceStatus.fromJson(await client.get('/attendance', query: {'month': ?month}));

  Future<AttendanceStatus> checkIn() async =>
      AttendanceStatus.fromJson(await client.post('/attendance', const {}));

  Future<AdStatus> adStatus() async => AdStatus.fromJson(await client.get('/ads/status'));

  /// 개발 서버 전용: 테스트 광고는 SSV 콜백이 오지 않으므로 같은 지급 경로를 직접 부른다
  Future<AdStatus> devAdReward() async =>
      AdStatus.fromJson(await client.post('/ads/dev-reward', const {}));

  Future<LedgerPage> history({String? cursor}) async {
    final j = await client.get('/points/history', query: {'cursor': ?cursor});
    return LedgerPage([
      for (final e in j['entries'] as List) LedgerEntry.fromJson(e as Map<String, dynamic>),
    ], j['nextCursor'] as String?);
  }

  Future<AchievementBook> achievements() async {
    final j = await client.get('/achievements');
    return AchievementBook([
      for (final a in j['achievements'] as List) Achievement.fromJson(a as Map<String, dynamic>),
    ], j['titleAchievementId'] as String?);
  }

  Future<List<Achievement>> unseen() async {
    final j = await client.get('/achievements/unseen');
    return [
      for (final a in j['achievements'] as List)
        Achievement.fromJson({...a as Map<String, dynamic>, 'achieved': true}),
    ];
  }

  Future<void> markSeen(List<String> ids) => client.post('/achievements/seen', {'ids': ids});

  Future<void> setTitle(String? achievementId) =>
      client.put('/me/title', {'achievementId': achievementId});
}

final rewardsApiProvider = Provider<RewardsApi>((ref) => RewardsApi(ref.watch(apiClientProvider)));

Duration? _noRetry(int count, Object error) => null;

final attendanceProvider = FutureProvider<AttendanceStatus>(
  (ref) => ref.watch(rewardsApiProvider).attendance(),
  retry: _noRetry,
);

final adStatusProvider = FutureProvider<AdStatus>(
  (ref) => ref.watch(rewardsApiProvider).adStatus(),
  retry: _noRetry,
);

final achievementBookProvider = FutureProvider.autoDispose<AchievementBook>(
  (ref) => ref.watch(rewardsApiProvider).achievements(),
  retry: _noRetry,
);
