import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/routes.dart';
import '../../app/theme.dart';
import '../../core/api_client.dart';
import '../../core/config.dart';
import '../../ui/widgets.dart';
import '../auth/auth_api.dart';
import '../auth/session.dart';

class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key});

  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen> {
  SocialProvider? _busy;
  String? _error;

  Future<void> _signIn(SocialProvider provider, {String? devId}) async {
    setState(() {
      _busy = provider;
      _error = null;
    });
    try {
      await ref.read(sessionProvider.notifier).signIn(provider, devId: devId);
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _busy = null);
    }
  }

  Future<void> _devLogin() async {
    final controller = TextEditingController(text: 'tester1');
    final id = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('개발용 로그인'),
        content: TextField(
          controller: controller,
          decoration: const InputDecoration(labelText: '테스트 계정 ID (영문·숫자)'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('취소')),
          TextButton(
            onPressed: () => Navigator.pop(context, controller.text.trim()),
            child: const Text('로그인'),
          ),
        ],
      ),
    );
    if (id != null && id.isNotEmpty) await _signIn(SocialProvider.dev, devId: id);
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final session = ref.watch(sessionProvider);
    final notice = session is SignedOut ? session.notice : null;
    final busy = _busy != null;
    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: Column(
            children: [
              const Spacer(flex: 3),
              const BobbingGoat(size: 170),
              const SizedBox(height: 16),
              Text('메에일', style: text.displaySmall),
              const SizedBox(height: 8),
              Text('염소 우체부가 전해 주는 느린 편지', style: text.bodyLarge),
              const Spacer(flex: 2),
              if (_error != null || notice != null) ...[
                NoticeBox(_error ?? notice!),
                const SizedBox(height: 16),
              ],
              ChunkyButton(
                label: '카카오로 시작하기',
                color: const Color(0xFFFEE500),
                foreground: const Color(0xD9000000),
                leading: const Icon(Icons.chat_bubble_rounded, size: 20, color: Color(0xFF191919)),
                loading: _busy == SocialProvider.kakao,
                onPressed: busy ? null : () => _signIn(SocialProvider.kakao),
              ),
              const SizedBox(height: 12),
              ChunkyButton(
                label: '구글로 시작하기',
                color: Colors.white,
                leading: const _GoogleMark(),
                loading: _busy == SocialProvider.google,
                onPressed: busy ? null : () => _signIn(SocialProvider.google),
              ),
              if (AppConfig.devLogin) ...[
                const SizedBox(height: 12),
                ChunkyButton(
                  label: '개발용 로그인',
                  color: Palette.sky,
                  loading: _busy == SocialProvider.dev,
                  onPressed: busy ? null : _devLogin,
                ),
              ],
              const SizedBox(height: 16),
              Wrap(
                alignment: WrapAlignment.center,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  TextButton(
                    onPressed: () => context.push(Routes.doc('terms')),
                    child: const Text('이용약관'),
                  ),
                  const Text('·'),
                  TextButton(
                    onPressed: () => context.push(Routes.doc('privacy')),
                    child: const Text('개인정보 안내'),
                  ),
                ],
              ),
              const SizedBox(height: 8),
            ],
          ),
        ),
      ),
    );
  }
}

/// 구글 로그인 버튼용 "G" 표시
class _GoogleMark extends StatelessWidget {
  const _GoogleMark();

  @override
  Widget build(BuildContext context) {
    return const Text(
      'G',
      style: TextStyle(
        fontFamily: Fonts.title,
        fontSize: 22,
        color: Color(0xFF4285F4),
        fontWeight: FontWeight.bold,
      ),
    );
  }
}
