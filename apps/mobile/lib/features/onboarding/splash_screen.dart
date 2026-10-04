import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../ui/widgets.dart';
import '../auth/session.dart';

/// 로그인 상태 복원 중 / 서버 연결 실패 화면
class SplashScreen extends ConsumerWidget {
  const SplashScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final session = ref.watch(sessionProvider);
    final text = Theme.of(context).textTheme;
    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Spacer(flex: 3),
              const Center(child: BobbingGoat(size: 170)),
              const SizedBox(height: 20),
              Text('메에일', textAlign: TextAlign.center, style: text.displaySmall),
              const Spacer(flex: 2),
              if (session is SessionUnreachable) ...[
                NoticeBox(session.message, icon: Icons.wifi_off_rounded),
                const SizedBox(height: 16),
                ChunkyButton(
                  label: '다시 시도',
                  onPressed: () => ref.read(sessionProvider.notifier).restore(),
                ),
              ] else
                Text('염소가 우편 가방을 챙기는 중…', textAlign: TextAlign.center, style: text.bodyLarge),
              const SizedBox(height: 40),
            ],
          ),
        ),
      ),
    );
  }
}
