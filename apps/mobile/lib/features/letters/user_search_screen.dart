import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/theme.dart';
import '../../core/api_client.dart';
import '../../ui/widgets.dart';
import 'letter_models.dart';
import 'letters_api.dart';

/// 닉네임으로 받는 사람 찾기(SPEC 5.2). 고르면 Person을 돌려준다.
class UserSearchScreen extends ConsumerStatefulWidget {
  const UserSearchScreen({super.key});

  @override
  ConsumerState<UserSearchScreen> createState() => _UserSearchScreenState();
}

class _UserSearchScreenState extends ConsumerState<UserSearchScreen> {
  final _controller = TextEditingController();
  Timer? _debounce;
  List<Person>? _results;
  String? _error;
  bool _loading = false;
  String _query = '';

  @override
  void dispose() {
    _debounce?.cancel();
    _controller.dispose();
    super.dispose();
  }

  void _onChanged(String v) {
    _debounce?.cancel();
    final q = v.trim();
    setState(() => _query = q);
    if (q.isEmpty) {
      setState(() => _results = null);
      return;
    }
    _debounce = Timer(const Duration(milliseconds: 300), () => _search(q));
  }

  Future<void> _search(String q) async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final users = await ref.read(lettersApiProvider).searchUsers(q);
      if (mounted && _controller.text.trim() == q) setState(() => _results = users);
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('받는 사람 찾기'), backgroundColor: Colors.transparent),
      body: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20),
        child: Column(
          children: [
            TextField(
              controller: _controller,
              autofocus: true,
              onChanged: _onChanged,
              textInputAction: TextInputAction.search,
              decoration: InputDecoration(
                hintText: '닉네임을 입력해 주세요',
                prefixIcon: const Icon(Icons.search_rounded),
                filled: true,
                fillColor: Colors.white,
                suffixIcon: _loading
                    ? const Padding(
                        padding: EdgeInsets.all(14),
                        child: SizedBox.square(
                          dimension: 18,
                          child: CircularProgressIndicator(strokeWidth: 2.5),
                        ),
                      )
                    : null,
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
            const SizedBox(height: 16),
            Expanded(child: _body()),
          ],
        ),
      ),
    );
  }

  Widget _body() {
    if (_error != null) {
      return Column(
        children: [
          NoticeBox(_error!),
          TextButton(onPressed: () => _search(_query), child: const Text('다시 시도')),
        ],
      );
    }
    if (_query.isEmpty) {
      return const _Hint(text: '편지를 받을 사람의 닉네임을 찾아보세요.\n똑같은 닉네임이 맨 위에 나와요.');
    }
    final results = _results;
    if (results == null) return const SizedBox.shrink();
    if (results.isEmpty) return const _Hint(text: '그런 닉네임은 아직 없어요.');
    return ListView.separated(
      itemCount: results.length,
      separatorBuilder: (_, _) => const SizedBox(height: 8),
      itemBuilder: (context, i) {
        final p = results[i];
        return Material(
          color: Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
            side: const BorderSide(color: Palette.outline, width: 2),
          ),
          child: ListTile(
            onTap: () => Navigator.pop(context, p),
            leading: const Icon(Icons.person_rounded, color: Palette.textBrown),
            title: Text(
              p.nickname,
              style: const TextStyle(
                fontFamily: Fonts.title,
                fontFamilyFallback: Fonts.fallback,
                fontSize: 18,
              ),
            ),
            subtitle: p.title == null ? null : Text(p.title!),
            trailing: const Icon(Icons.chevron_right_rounded),
          ),
        );
      },
    );
  }
}

class _Hint extends StatelessWidget {
  const _Hint({required this.text});
  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: 40),
    child: Column(
      children: [
        const IllustrationImage(Illustration.letter, size: 110),
        const SizedBox(height: 14),
        Text(text, textAlign: TextAlign.center, style: const TextStyle(height: 1.6)),
      ],
    ),
  );
}
