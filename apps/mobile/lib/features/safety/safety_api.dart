import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api_client.dart';
import '../auth/session.dart';

enum ReportTarget { letter, rollingEntry, user }

/// 신고 사유(서버 REPORT_REASONS와 같은 코드)
const reportReasons = <(String, String)>[
  ('ABUSE', '욕설·괴롭힘'),
  ('SEXUAL', '성적인 내용'),
  ('SPAM', '도배·광고'),
  ('PERSONAL_INFO', '개인정보 노출'),
  ('DANGER', '위험하거나 불법적인 내용'),
  ('OTHER', '기타'),
];

class BlockedUser {
  const BlockedUser(this.userId, this.nickname, this.blockedAt);
  final String userId;
  final String nickname;
  final DateTime blockedAt;
}

class Notice {
  const Notice({
    required this.id,
    required this.title,
    required this.body,
    required this.pinned,
    required this.publishedAt,
  });
  final String id;
  final String title;
  final String body;
  final bool pinned;
  final DateTime publishedAt;
}

class SafetyApi {
  SafetyApi(this.client);

  final ApiClient client;

  Future<void> report({
    required ReportTarget target,
    required String targetId,
    required String reason,
    String? detail,
  }) => client.post('/reports', {
    'targetType': switch (target) {
      ReportTarget.letter => 'LETTER',
      ReportTarget.rollingEntry => 'ROLLING_ENTRY',
      ReportTarget.user => 'USER',
    },
    'targetId': targetId,
    'reason': reason,
    if (detail != null && detail.trim().isNotEmpty) 'detail': detail.trim(),
  });

  Future<void> block(String userId) => client.post('/blocks', {'userId': userId});

  Future<void> unblock(String userId) => client.delete('/blocks/$userId');

  Future<List<BlockedUser>> blocks() async {
    final j = await client.get('/blocks');
    return [
      for (final b in j['blocks'] as List)
        BlockedUser(
          b['userId'] as String,
          b['nickname'] as String? ?? '(알 수 없음)',
          DateTime.parse(b['blockedAt'] as String),
        ),
    ];
  }

  Future<void> updateSettings({bool? randomReceive, bool? notifyEnabled}) => client.put(
    '/me/settings',
    {'randomReceive': ?randomReceive, 'notifyEnabled': ?notifyEnabled},
  );

  Future<List<Notice>> notices() async {
    final j = await client.get('/notices');
    return [
      for (final n in j['notices'] as List)
        Notice(
          id: n['id'] as String,
          title: n['title'] as String,
          body: n['body'] as String,
          pinned: n['pinned'] as bool? ?? false,
          publishedAt: DateTime.parse(n['publishedAt'] as String),
        ),
    ];
  }
}

final safetyApiProvider = Provider<SafetyApi>((ref) => SafetyApi(ref.watch(apiClientProvider)));

Duration? _noRetry(int count, Object error) => null;

final blocksProvider = FutureProvider.autoDispose<List<BlockedUser>>(
  (ref) => ref.watch(safetyApiProvider).blocks(),
  retry: _noRetry,
);

final noticesProvider = FutureProvider.autoDispose<List<Notice>>(
  (ref) => ref.watch(safetyApiProvider).notices(),
  retry: _noRetry,
);
