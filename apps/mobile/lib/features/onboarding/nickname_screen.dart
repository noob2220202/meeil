import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/theme.dart';
import '../../core/api_client.dart';
import '../../ui/widgets.dart';
import '../auth/session.dart';
import 'nickname_rules.dart';
import 'terms_screen.dart' show signupSteps;

enum _CheckState { idle, checking, ok, bad }

class NicknameScreen extends ConsumerStatefulWidget {
  const NicknameScreen({super.key});

  @override
  ConsumerState<NicknameScreen> createState() => _NicknameScreenState();
}

class _NicknameScreenState extends ConsumerState<NicknameScreen> {
  final _controller = TextEditingController();
  Timer? _debounce;
  _CheckState _check = _CheckState.idle;
  String? _message;
  String _checkedFor = '';
  bool _busy = false;

  @override
  void dispose() {
    _debounce?.cancel();
    _controller.dispose();
    super.dispose();
  }

  void _onChanged(String value) {
    _debounce?.cancel();
    final nick = value.trim();
    final local = localNicknameProblem(nick);
    setState(() {
      if (nick.isEmpty) {
        _check = _CheckState.idle;
        _message = null;
      } else if (local != null) {
        _check = _CheckState.bad;
        _message = local;
      } else {
        _check = _CheckState.checking;
        _message = null;
      }
    });
    if (nick.isEmpty || local != null) return;
    _debounce = Timer(const Duration(milliseconds: 400), () => _remoteCheck(nick));
  }

  Future<void> _remoteCheck(String nick) async {
    try {
      final r = await ref.read(authApiProvider).checkNickname(nick);
      if (!mounted || _controller.text.trim() != nick) return;
      setState(() {
        _check = r.available ? _CheckState.ok : _CheckState.bad;
        _message = r.message;
        _checkedFor = nick;
      });
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _check = _CheckState.bad;
        _message = e.message;
      });
    }
  }

  Future<void> _submit() async {
    setState(() => _busy = true);
    try {
      final me = await ref.read(authApiProvider).setNickname(_controller.text.trim());
      ref.read(sessionProvider.notifier).update(me);
    } on ApiException catch (e) {
      if (mounted) {
        setState(() {
          _check = _CheckState.bad;
          _message = e.message;
        });
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final canSubmit = _check == _CheckState.ok && _checkedFor == _controller.text.trim();
    final statusColor = switch (_check) {
      _CheckState.ok => const Color(0xFF2E8B57),
      _CheckState.bad => const Color(0xFFD9485F),
      _ => Palette.textBrown,
    };
    return StepScaffold(
      step: 3,
      totalSteps: signupSteps,
      title: '뭐라고 불러 드릴까요?',
      subtitle: '편지에 내 이름으로 적혀요.\n한 번 정하면 30일 동안 바꿀 수 없어요.',
      bottom: ChunkyButton(
        label: '이걸로 할게요',
        color: Palette.yellow,
        loading: _busy,
        onPressed: canSubmit ? _submit : null,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TextField(
            controller: _controller,
            onChanged: _onChanged,
            autofocus: true,
            maxLength: nicknameMax,
            textInputAction: TextInputAction.done,
            onSubmitted: (_) => canSubmit ? _submit() : null,
            style: const TextStyle(fontFamily: Fonts.title, fontSize: 22, color: Palette.textBrown),
            decoration: InputDecoration(
              hintText: '예) 뽀얀염소',
              filled: true,
              fillColor: Colors.white,
              counterStyle: const TextStyle(color: Palette.textBrown),
              suffixIcon: switch (_check) {
                _CheckState.checking => const Padding(
                  padding: EdgeInsets.all(14),
                  child: SizedBox.square(
                    dimension: 18,
                    child: CircularProgressIndicator(strokeWidth: 2.5),
                  ),
                ),
                _CheckState.ok => const Icon(Icons.check_circle_rounded, color: Color(0xFF2E8B57)),
                _CheckState.bad => const Icon(Icons.error_rounded, color: Color(0xFFD9485F)),
                _CheckState.idle => null,
              },
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(16),
                borderSide: const BorderSide(color: Palette.outline, width: 2.5),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(16),
                borderSide: const BorderSide(color: Palette.outline, width: 3),
              ),
            ),
          ),
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 200),
            child: Text(
              _message ?? '한글·영문·숫자로 2~10자',
              key: ValueKey(_message),
              style: TextStyle(color: statusColor, fontSize: 15),
            ),
          ),
        ],
      ),
    );
  }
}
