import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/push.dart';
import '../features/auth/session.dart';
import '../features/letters/mailbox_providers.dart';
import 'router.dart';

/// 로그인한 동안 푸시를 받는다. 알림을 누르면 해당 화면으로.
final pushServiceProvider = Provider<PushService>((ref) {
  final service = PushService(
    client: ref.watch(apiClientProvider),
    onOpen: (route) => ref.read(routerProvider).push(route),
    onMessage: () => refreshMailboxes(ref),
  );
  ref.onDispose(service.stop);
  ref.read(sessionProvider.notifier).beforeSignOut = service.stop;
  return service;
});
