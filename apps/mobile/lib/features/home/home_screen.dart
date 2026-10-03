import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/theme.dart';
import '../../data/regions.dart';

/// M0 빈 화면: 앱 기동과 지역 데이터 로드만 확인한다. 지도는 M2에서.
class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final regions = ref.watch(regionDataProvider);
    final text = Theme.of(context).textTheme;
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text('메에일', style: text.displaySmall),
                const SizedBox(height: 8),
                Text('우체부 염소들이 출근 준비 중이에요', style: text.bodyLarge),
                const SizedBox(height: 24),
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
                    child: TextButton(
                      onPressed: () => ref.invalidate(regionDataProvider),
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
