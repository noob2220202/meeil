import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../app/theme.dart';

enum Illustration { goat, letter, scroll }

class IllustrationImage extends StatelessWidget {
  const IllustrationImage(this.kind, {super.key, this.size = 180});

  final Illustration kind;
  final double size;

  @override
  Widget build(BuildContext context) {
    final name = switch (kind) {
      Illustration.goat => 'goat_face',
      Illustration.letter => 'letter',
      Illustration.scroll => 'scroll',
    };
    return SvgPicture.asset('assets/illustrations/$name.svg', width: size, height: size);
  }
}

/// 위아래로 살짝 통통 튀며 좌우로 기우뚱하는 염소(대기 화면용).
/// 시스템 "애니메이션 줄이기"가 켜져 있으면 멈춰 있다.
class BobbingGoat extends StatefulWidget {
  const BobbingGoat({super.key, this.size = 180});

  final double size;

  @override
  State<BobbingGoat> createState() => _BobbingGoatState();
}

class _BobbingGoatState extends State<BobbingGoat> with SingleTickerProviderStateMixin {
  late final _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 1100));

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (MediaQuery.disableAnimationsOf(context)) {
      _c.stop();
    } else if (!_c.isAnimating) {
      _c.repeat(reverse: true);
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _c,
      builder: (context, child) {
        final t = Curves.easeInOut.transform(_c.value);
        return Transform.translate(
          offset: Offset(0, -8 * t),
          child: Transform.rotate(angle: (t - 0.5) * 0.12, child: child),
        );
      },
      child: IllustrationImage(Illustration.goat, size: widget.size),
    );
  }
}

/// 굵은 갈색 외곽선 + 눌리면 살짝 내려앉는 통통한 버튼
class ChunkyButton extends StatefulWidget {
  const ChunkyButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.color = Palette.mint,
    this.foreground = Palette.textBrown,
    this.leading,
    this.loading = false,
  });

  final String label;
  final VoidCallback? onPressed;
  final Color color;
  final Color foreground;
  final Widget? leading;
  final bool loading;

  @override
  State<ChunkyButton> createState() => _ChunkyButtonState();
}

class _ChunkyButtonState extends State<ChunkyButton> {
  bool _down = false;

  @override
  Widget build(BuildContext context) {
    final enabled = widget.onPressed != null && !widget.loading;
    const depth = 4.0;
    final pressed = _down && enabled;
    return Semantics(
      button: true,
      enabled: enabled,
      label: widget.label,
      child: GestureDetector(
        onTapDown: enabled ? (_) => setState(() => _down = true) : null,
        onTapCancel: () => setState(() => _down = false),
        onTapUp: enabled ? (_) => setState(() => _down = false) : null,
        onTap: enabled ? widget.onPressed : null,
        child: AnimatedOpacity(
          duration: const Duration(milliseconds: 150),
          opacity: enabled || widget.loading ? 1 : 0.45,
          child: SizedBox(
            height: 56 + depth,
            child: Stack(
              children: [
                // 그림자 판
                Positioned.fill(
                  top: depth,
                  child: Container(
                    decoration: BoxDecoration(
                      color: Palette.outline,
                      borderRadius: BorderRadius.circular(18),
                    ),
                  ),
                ),
                AnimatedPositioned(
                  duration: const Duration(milliseconds: 70),
                  left: 0,
                  right: 0,
                  top: pressed ? depth : 0,
                  height: 56,
                  child: Container(
                    decoration: BoxDecoration(
                      color: widget.color,
                      borderRadius: BorderRadius.circular(18),
                      border: Border.all(color: Palette.outline, width: 2.5),
                    ),
                    alignment: Alignment.center,
                    child: widget.loading
                        ? SizedBox.square(
                            dimension: 22,
                            child: CircularProgressIndicator(
                              strokeWidth: 2.5,
                              color: widget.foreground,
                            ),
                          )
                        : Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              if (widget.leading != null) ...[
                                widget.leading!,
                                const SizedBox(width: 10),
                              ],
                              Text(
                                widget.label,
                                style: TextStyle(
                                  fontFamily: Fonts.title,
                                  fontSize: 18,
                                  color: widget.foreground,
                                ),
                              ),
                            ],
                          ),
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

/// 분홍 말풍선 형태의 오류/안내 문구
class NoticeBox extends StatelessWidget {
  const NoticeBox(
    this.message, {
    super.key,
    this.color = Palette.pink,
    this.icon = Icons.info_outline,
  });

  final String message;
  final Color color;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Palette.outline, width: 2),
      ),
      child: Row(
        children: [
          Icon(icon, color: Palette.textBrown, size: 20),
          const SizedBox(width: 8),
          Expanded(
            child: Text(message, style: const TextStyle(color: Palette.textBrown)),
          ),
        ],
      ),
    );
  }
}

/// 가입 단계 공통 틀: 진행 점, 제목, 설명, 내용, 하단 버튼
class StepScaffold extends StatelessWidget {
  const StepScaffold({
    super.key,
    required this.step,
    required this.totalSteps,
    required this.title,
    this.subtitle,
    required this.child,
    required this.bottom,
  });

  final int step;
  final int totalSteps;
  final String title;
  final String? subtitle;
  final Widget child;
  final Widget bottom;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 16, 24, 20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              StepDots(current: step, total: totalSteps),
              const SizedBox(height: 28),
              Text(title, style: text.headlineMedium),
              if (subtitle != null) ...[
                const SizedBox(height: 10),
                Text(subtitle!, style: text.bodyLarge?.copyWith(height: 1.5)),
              ],
              const SizedBox(height: 24),
              Expanded(child: child),
              bottom,
            ],
          ),
        ),
      ),
    );
  }
}

class StepDots extends StatelessWidget {
  const StepDots({super.key, required this.current, required this.total});

  final int current;
  final int total;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: '$total단계 중 $current단계',
      child: Row(
        children: [
          for (var i = 1; i <= total; i++)
            AnimatedContainer(
              duration: const Duration(milliseconds: 250),
              margin: const EdgeInsets.only(right: 6),
              width: i == current ? 26 : 10,
              height: 10,
              decoration: BoxDecoration(
                color: i <= current ? Palette.outline : Palette.outline.withValues(alpha: 0.2),
                borderRadius: BorderRadius.circular(5),
              ),
            ),
        ],
      ),
    );
  }
}
