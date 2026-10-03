import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/routes.dart';
import '../../app/theme.dart';
import '../../core/api_client.dart';
import '../../ui/widgets.dart';
import '../auth/session.dart';

const signupSteps = 4;

class TermsScreen extends ConsumerStatefulWidget {
  const TermsScreen({super.key});

  @override
  ConsumerState<TermsScreen> createState() => _TermsScreenState();
}

class _TermsScreenState extends ConsumerState<TermsScreen> {
  bool _terms = false;
  bool _privacy = false;
  bool _busy = false;
  String? _error;

  bool get _all => _terms && _privacy;

  Future<void> _submit() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final me = await ref.read(authApiProvider).agree();
      ref.read(sessionProvider.notifier).update(me);
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return StepScaffold(
      step: 1,
      totalSteps: signupSteps,
      title: '반가워요!\n약관에 동의해 주세요',
      subtitle: '메에일을 쓰려면 아래 내용에 동의가 필요해요.',
      bottom: Column(
        children: [
          if (_error != null) ...[NoticeBox(_error!), const SizedBox(height: 12)],
          ChunkyButton(
            label: '동의하고 계속',
            color: Palette.yellow,
            loading: _busy,
            onPressed: _all ? _submit : null,
          ),
        ],
      ),
      child: Column(
        children: [
          _CheckRow(
            label: '전체 동의',
            bold: true,
            value: _all,
            onChanged: (v) => setState(() => _terms = _privacy = v),
          ),
          const Divider(height: 24, color: Palette.outline, thickness: 1),
          _CheckRow(
            label: '(필수) 이용약관',
            value: _terms,
            onChanged: (v) => setState(() => _terms = v),
            onView: () => context.push(Routes.doc('terms')),
          ),
          _CheckRow(
            label: '(필수) 개인정보 수집·이용',
            value: _privacy,
            onChanged: (v) => setState(() => _privacy = v),
            onView: () => context.push(Routes.doc('privacy')),
          ),
        ],
      ),
    );
  }
}

class _CheckRow extends StatelessWidget {
  const _CheckRow({
    required this.label,
    required this.value,
    required this.onChanged,
    this.onView,
    this.bold = false,
  });

  final String label;
  final bool value;
  final ValueChanged<bool> onChanged;
  final VoidCallback? onView;
  final bool bold;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: () => onChanged(!value),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 10),
        child: Row(
          children: [
            AnimatedContainer(
              duration: const Duration(milliseconds: 150),
              width: 28,
              height: 28,
              decoration: BoxDecoration(
                color: value ? Palette.mint : Colors.white,
                borderRadius: BorderRadius.circular(9),
                border: Border.all(color: Palette.outline, width: 2.5),
              ),
              child: value
                  ? const Icon(Icons.check_rounded, size: 20, color: Palette.textBrown)
                  : null,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                label,
                style: TextStyle(
                  fontSize: bold ? 18 : 16,
                  fontFamily: bold ? Fonts.title : null,
                  fontFamilyFallback: Fonts.fallback,
                  color: Palette.textBrown,
                ),
              ),
            ),
            if (onView != null) TextButton(onPressed: onView, child: const Text('보기')),
          ],
        ),
      ),
    );
  }
}
