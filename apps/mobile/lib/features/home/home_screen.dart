import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/theme.dart';
import '../../data/regions.dart';
import '../../ui/widgets.dart';
import '../auth/session.dart';

/// 임시 홈: 로그인 유지 확인용. 일러스트 지도는 M2에서 이 자리에 들어온다.
class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final session = ref.watch(sessionProvider);
    final me = session is SignedIn ? session.me : null;
    final regions = ref.watch(regionDataProvider);
    final text = Theme.of(context).textTheme;
    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: Column(
            children: [
              Align(
                alignment: Alignment.centerRight,
                child: TextButton.icon(
                  onPressed: () => ref.read(sessionProvider.notifier).signOut(),
                  icon: const Icon(Icons.logout_rounded, size: 18),
                  label: const Text('로그아웃'),
                ),
              ),
              const Spacer(),
              const BobbingGoat(size: 150),
              const SizedBox(height: 20),
              Text(
                me?.nickname != null ? '${me!.nickname}님, 어서 와요!' : '메에일',
                textAlign: TextAlign.center,
                style: text.headlineMedium,
              ),
              const SizedBox(height: 8),
              Text('우체부 염소들이 출근 준비 중이에요', style: text.bodyLarge),
              const SizedBox(height: 24),
              Wrap(
                spacing: 10,
                runSpacing: 10,
                alignment: WrapAlignment.center,
                children: [
                  if (me != null) _Chip(color: Palette.yellow, child: Text('${me.pointsBalance}P')),
                  regions.when(
                    loading: () => const _Chip(
                      color: Palette.sky,
                      child: SizedBox.square(
                        dimension: 18,
                        child: CircularProgressIndicator(strokeWidth: 2.5),
                      ),
                    ),
                    error: (e, _) => _Chip(
                      color: Palette.pink,
                      child: GestureDetector(
                        onTap: () => ref.invalidate(regionDataProvider),
                        child: const Text('지도를 불러오지 못했어요 · 다시 시도'),
                      ),
                    ),
                    data: (d) => _Chip(
                      color: Palette.mint,
                      child: Text('${d.provinces.length}개 시도 · ${d.regions.length}개 시'),
                    ),
                  ),
                ],
              ),
              const Spacer(flex: 2),
            ],
          ),
        ),
      ),
    );
  }
}

class _Chip extends StatelessWidget {
  const _Chip({required this.color, required this.child});

  final Color color;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Palette.outline, width: 2),
      ),
      child: child,
    );
  }
}
