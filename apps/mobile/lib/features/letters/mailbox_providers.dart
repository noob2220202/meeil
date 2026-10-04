import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'letter_models.dart';
import 'letters_api.dart';

class MailboxState {
  const MailboxState(this.letters, this.nextCursor, {this.loadingMore = false});

  final List<Letter> letters;
  final String? nextCursor;
  final bool loadingMore;

  bool get hasMore => nextCursor != null;
}

/// 편지함 한 칸(받은·보낸·휴지통). 커서로 더 불러온다.
class MailboxController extends AsyncNotifier<MailboxState> {
  MailboxController(this.box);
  final MailBox box;

  @override
  Future<MailboxState> build() async {
    final page = await ref.read(lettersApiProvider).list(box);
    return MailboxState(page.letters, page.nextCursor);
  }

  Future<void> loadMore() async {
    final cur = state.value;
    if (cur == null || !cur.hasMore || cur.loadingMore) return;
    state = AsyncData(MailboxState(cur.letters, cur.nextCursor, loadingMore: true));
    try {
      final page = await ref.read(lettersApiProvider).list(box, cursor: cur.nextCursor);
      state = AsyncData(MailboxState([...cur.letters, ...page.letters], page.nextCursor));
    } catch (_) {
      state = AsyncData(MailboxState(cur.letters, cur.nextCursor));
    }
  }

  Future<void> refresh() async {
    state = await AsyncValue.guard(build);
  }

  /// 상세에서 바뀐 편지 반영(읽음 등)
  void replace(Letter l) {
    final cur = state.value;
    if (cur == null) return;
    state = AsyncData(
      MailboxState([for (final x in cur.letters) x.id == l.id ? l : x], cur.nextCursor),
    );
  }

  void remove(String id) {
    final cur = state.value;
    if (cur == null) return;
    state = AsyncData(MailboxState(cur.letters.where((x) => x.id != id).toList(), cur.nextCursor));
  }
}

final mailboxProvider = AsyncNotifierProvider.family<MailboxController, MailboxState, MailBox>(
  MailboxController.new,
);

/// 안 읽은 편지 수(편지함 탭 배지). 앱이 켜져 있는 동안 1분마다 갱신.
/// 타이머는 provider가 사라질 때(로그아웃 등) 반드시 멈춘다.
class UnreadCountController extends AsyncNotifier<int> {
  Timer? _timer;

  @override
  Future<int> build() async {
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(minutes: 1), (_) => _poll());
    ref.onDispose(() => _timer?.cancel());
    return ref.read(lettersApiProvider).unreadCount();
  }

  Future<void> _poll() async {
    try {
      state = AsyncData(await ref.read(lettersApiProvider).unreadCount());
    } catch (_) {
      // 네트워크 오류면 이전 값 유지
    }
  }
}

final unreadCountProvider = AsyncNotifierProvider<UnreadCountController, int>(
  UnreadCountController.new,
);

/// 편지 하나를 바꾼 뒤 모든 편지함 새로고침
void refreshMailboxes(Ref ref) {
  for (final b in MailBox.values) {
    ref.invalidate(mailboxProvider(b));
  }
  ref.invalidate(unreadCountProvider);
}

/// 위젯용
void refreshMailboxesFromWidget(WidgetRef ref) {
  for (final b in MailBox.values) {
    ref.invalidate(mailboxProvider(b));
  }
  ref.invalidate(unreadCountProvider);
}
