import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api_client.dart';
import '../auth/session.dart';
import '../letters/letter_models.dart';
import 'rolling_models.dart';

class RollingApi {
  RollingApi(this.client);

  final ApiClient client;

  Future<RollingSummary> summary() async =>
      RollingSummary.fromJson(await client.get('/rolling/current/all'));

  Future<RollingView> current(RollingLevel level) async =>
      RollingView.fromJson(await client.get('/rolling/current', query: {'level': level.api}));

  Future<RollingView> get(String id) async =>
      RollingView.fromJson(await client.get('/rolling/$id'));

  Future<RollingEntry> join(String paperId, String body, List<PlacedSticker> stickers) async =>
      RollingEntry.fromJson(
        await client.post('/rolling/$paperId/entries', {
          'body': body,
          'stickers': [for (final s in stickers) s.toJson()],
        }),
      );

  Future<List<RollingPaper>> album() async {
    final j = await client.get('/rolling/album');
    return [for (final p in j['papers'] as List) RollingPaper.fromJson(p as Map<String, dynamic>)];
  }
}

final rollingApiProvider = Provider<RollingApi>((ref) => RollingApi(ref.watch(apiClientProvider)));

/// 롤링 탭 요약. 내 시가 바뀌면 다시 불러온다.
final rollingSummaryProvider = FutureProvider<RollingSummary>(
  (ref) => ref.watch(rollingApiProvider).summary(),
  retry: _noRetry,
);

/// 자동 재시도 대신 화면의 "다시 시도" 버튼(403 등은 다시 해도 같다)
Duration? _noRetry(int count, Object error) => null;

/// 두루마리 한 장(진행 중이면 그 지역 사람만, 마감이면 참여자만)
class RollingPaperController extends AsyncNotifier<RollingView> {
  RollingPaperController(this.id);
  final String id;

  @override
  Future<RollingView> build() => ref.read(rollingApiProvider).get(id);

  Future<void> refresh() async {
    state = await AsyncValue.guard(build);
  }

  /// 한마디 남기기. 실패하면 ApiException을 그대로 던진다.
  Future<void> join(String body, List<PlacedSticker> stickers) async {
    final e = await ref.read(rollingApiProvider).join(id, body, stickers);
    final cur = state.value;
    if (cur != null) state = AsyncData(cur.withEntry(e));
    ref.invalidate(rollingSummaryProvider);
  }
}

final rollingPaperProvider = AsyncNotifierProvider.autoDispose
    .family<RollingPaperController, RollingView, String>(
      RollingPaperController.new,
      retry: _noRetry,
    );

final rollingAlbumProvider = FutureProvider.autoDispose<List<RollingPaper>>(
  (ref) => ref.watch(rollingApiProvider).album(),
  retry: _noRetry,
);
