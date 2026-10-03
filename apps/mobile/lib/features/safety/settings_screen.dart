import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/theme.dart';
import '../../core/api_client.dart';
import '../../core/sound.dart';
import '../../ui/widgets.dart';
import '../auth/session.dart';
import 'safety_api.dart';

/// 설정 (SPEC 9.1, 10): 랜덤 편지 받기, 알림, 차단 목록, 공지, 약관
class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({super.key});

  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> {
  bool _saving = false;

  Future<void> _set({bool? randomReceive, bool? notifyEnabled}) async {
    setState(() => _saving = true);
    try {
      await ref
          .read(safetyApiProvider)
          .updateSettings(randomReceive: randomReceive, notifyEnabled: notifyEnabled);
      await ref.read(sessionProvider.notifier).refreshMe();
    } on ApiException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final session = ref.watch(sessionProvider);
    final me = session is SignedIn ? session.me : null;
    final blocks = ref.watch(blocksProvider);
    return Scaffold(
      backgroundColor: Palette.cream,
      appBar: AppBar(title: const Text('설정')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _Group(
            children: [
              SwitchListTile(
                key: const ValueKey('switch-random'),
                value: me?.randomReceive ?? true,
                onChanged: me == null || _saving ? null : (v) => _set(randomReceive: v),
                title: const Text('랜덤 편지 받기'),
                subtitle: const Text('끄면 모르는 사람이 보낸 랜덤 편지가 나에게 오지 않아요.'),
              ),
              const Divider(height: 1),
              SwitchListTile(
                key: const ValueKey('switch-notify'),
                value: me?.notifyEnabled ?? true,
                onChanged: me == null || _saving ? null : (v) => _set(notifyEnabled: v),
                title: const Text('알림 받기'),
                subtitle: const Text('편지 도착, 우리 동네에 온 염소, 공지를 알려 줘요.'),
              ),
              const Divider(height: 1),
              SwitchListTile(
                key: const ValueKey('switch-sound'),
                value: ref.watch(soundEnabledProvider),
                onChanged: (v) {
                  ref.read(soundEnabledProvider.notifier).set(v);
                  if (v) playSfx(ref, Sfx.bleatShort);
                },
                title: const Text('효과음'),
                subtitle: const Text('염소 울음, 편지 여는 소리 같은 작은 소리. 무음 모드에서는 울리지 않아요.'),
              ),
            ],
          ),
          const SizedBox(height: 18),
          const _Heading('차단한 사람'),
          blocks.when(
            loading: () => const Padding(
              padding: EdgeInsets.all(16),
              child: Center(child: CircularProgressIndicator()),
            ),
            error: (e, _) => Column(
              children: [
                const NoticeBox('차단 목록을 불러오지 못했어요.'),
                TextButton(
                  onPressed: () => ref.invalidate(blocksProvider),
                  child: const Text('다시 시도'),
                ),
              ],
            ),
            data: (list) => list.isEmpty
                ? const _Group(
                    children: [
                      Padding(
                        padding: EdgeInsets.all(16),
                        child: Text('차단한 사람이 없어요.', textAlign: TextAlign.center),
                      ),
                    ],
                  )
                : _Group(
                    children: [
                      for (final (i, b) in list.indexed) ...[
                        if (i > 0) const Divider(height: 1),
                        ListTile(
                          leading: const Icon(Icons.block_rounded),
                          title: Text(b.nickname),
                          trailing: TextButton(
                            key: ValueKey('unblock-${b.userId}'),
                            onPressed: () async {
                              try {
                                await ref.read(safetyApiProvider).unblock(b.userId);
                                ref.invalidate(blocksProvider);
                                if (context.mounted) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(content: Text('${b.nickname}님 차단을 풀었어요.')),
                                  );
                                }
                              } on ApiException catch (e) {
                                if (context.mounted) {
                                  ScaffoldMessenger.of(context)
                                      .showSnackBar(SnackBar(content: Text(e.message)));
                                }
                              }
                            },
                            child: const Text('차단 풀기'),
                          ),
                        ),
                      ],
                    ],
                  ),
          ),
          const SizedBox(height: 18),
          const _Heading('안내'),
          _Group(
            children: [
              ListTile(
                key: const ValueKey('open-notices'),
                leading: const Icon(Icons.campaign_rounded),
                title: const Text('공지사항'),
                trailing: const Icon(Icons.chevron_right_rounded),
                onTap: () => context.push('/notices'),
              ),
              const Divider(height: 1),
              ListTile(
                leading: const Icon(Icons.description_rounded),
                title: const Text('이용약관'),
                trailing: const Icon(Icons.chevron_right_rounded),
                onTap: () => context.push('/docs/terms'),
              ),
              const Divider(height: 1),
              ListTile(
                leading: const Icon(Icons.privacy_tip_rounded),
                title: const Text('개인정보 처리방침'),
                trailing: const Icon(Icons.chevron_right_rounded),
                onTap: () => context.push('/docs/privacy'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _Heading extends StatelessWidget {
  const _Heading(this.text);
  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(4, 0, 4, 8),
    child: Text(
      text,
      style: const TextStyle(
        fontFamily: Fonts.title,
        fontFamilyFallback: Fonts.fallback,
        fontSize: 16,
      ),
    ),
  );
}

class _Group extends StatelessWidget {
  const _Group({required this.children});
  final List<Widget> children;

  @override
  Widget build(BuildContext context) => Material(
    color: Colors.white,
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(16),
      side: const BorderSide(color: Palette.outline, width: 2),
    ),
    clipBehavior: Clip.antiAlias,
    child: Column(children: children),
  );
}
