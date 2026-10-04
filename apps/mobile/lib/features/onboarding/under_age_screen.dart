import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../ui/widgets.dart';
import '../auth/session.dart';

/// 만 14세 미만 가입 불가 안내 (SPEC 8). 서버는 이미 계정을 지운 상태.
class UnderAgeScreen extends ConsumerWidget {
  const UnderAgeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final text = Theme.of(context).textTheme;
    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: Column(
            children: [
              const Spacer(),
              const IllustrationImage(Illustration.goat, size: 160),
              const SizedBox(height: 28),
              Text('만 14세가 되면\n다시 만나요!', textAlign: TextAlign.center, style: text.headlineMedium),
              const SizedBox(height: 14),
              Text(
                '메에일은 만 14세 이상부터 이용할 수 있어요.\n입력한 정보는 저장하지 않고 바로 지웠어요.',
                textAlign: TextAlign.center,
                style: text.bodyLarge?.copyWith(height: 1.6),
              ),
              const Spacer(),
              ChunkyButton(
                label: '처음으로',
                onPressed: () => ref.read(sessionProvider.notifier).clearNotice(),
              ),
              const SizedBox(height: 20),
            ],
          ),
        ),
      ),
    );
  }
}
