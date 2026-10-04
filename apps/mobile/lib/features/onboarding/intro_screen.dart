import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/theme.dart';
import '../../core/app_flags.dart';
import '../../ui/widgets.dart';

class _Cut {
  const _Cut(this.illustration, this.title, this.body, this.background);

  final Illustration illustration;
  final String title;
  final String body;
  final Color background;
}

const _cuts = [
  _Cut(Illustration.goat, '우체부 염소들이\n전국을 돌아다녀요', '오늘은 어느 시에 와 있을까요?\n지도에서 염소를 찾아보세요.', Palette.sky),
  _Cut(
    Illustration.letter,
    '염소가 오면\n편지를 맡겨요',
    '이름을 밝히고 쓰는 다정한 편지.\n느리지만 3일 안에는 꼭 도착해요.',
    Palette.pink,
  ),
  _Cut(
    Illustration.scroll,
    '롤링페이퍼에\n다 같이 한마디',
    '우리 시, 우리 도, 전국 사람들과\n한 장의 두루마리를 채워요.',
    Palette.mint,
  ),
];

/// 온보딩 3컷 (SPEC 10장). 처음 한 번만 보여준다.
class IntroScreen extends ConsumerStatefulWidget {
  const IntroScreen({super.key});

  @override
  ConsumerState<IntroScreen> createState() => _IntroScreenState();
}

class _IntroScreenState extends ConsumerState<IntroScreen> {
  final _pages = PageController();
  int _index = 0;

  @override
  void dispose() {
    _pages.dispose();
    super.dispose();
  }

  void _finish() => ref.read(appFlagsProvider.notifier).markIntroSeen();

  @override
  Widget build(BuildContext context) {
    final last = _index == _cuts.length - 1;
    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            Align(
              alignment: Alignment.centerRight,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(0, 8, 12, 0),
                child: TextButton(
                  onPressed: last ? null : _finish,
                  child: Text(last ? '' : '건너뛰기'),
                ),
              ),
            ),
            Expanded(
              child: PageView.builder(
                controller: _pages,
                itemCount: _cuts.length,
                onPageChanged: (i) => setState(() => _index = i),
                itemBuilder: (context, i) => _CutView(_cuts[i]),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 0, 24, 20),
              child: Column(
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      for (var i = 0; i < _cuts.length; i++)
                        AnimatedContainer(
                          duration: const Duration(milliseconds: 250),
                          margin: const EdgeInsets.symmetric(horizontal: 4),
                          width: i == _index ? 24 : 10,
                          height: 10,
                          decoration: BoxDecoration(
                            color: i == _index
                                ? Palette.outline
                                : Palette.outline.withValues(alpha: 0.2),
                            borderRadius: BorderRadius.circular(5),
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 24),
                  ChunkyButton(
                    label: last ? '시작하기' : '다음',
                    color: last ? Palette.yellow : Palette.mint,
                    onPressed: last
                        ? _finish
                        : () => _pages.nextPage(
                            duration: const Duration(milliseconds: 350),
                            curve: Curves.easeOutCubic,
                          ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _CutView extends StatelessWidget {
  const _CutView(this.cut);

  final _Cut cut;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 260,
            height: 260,
            decoration: BoxDecoration(
              color: cut.background,
              shape: BoxShape.circle,
              border: Border.all(color: Palette.outline, width: 3),
            ),
            alignment: Alignment.center,
            child: IllustrationImage(cut.illustration, size: 190),
          ),
          const SizedBox(height: 40),
          Text(
            cut.title,
            textAlign: TextAlign.center,
            style: text.headlineMedium?.copyWith(height: 1.3),
          ),
          const SizedBox(height: 14),
          Text(cut.body, textAlign: TextAlign.center, style: text.bodyLarge?.copyWith(height: 1.6)),
        ],
      ),
    );
  }
}
