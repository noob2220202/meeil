import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/theme.dart';
import '../../core/api_client.dart';
import '../../ui/widgets.dart';
import 'safety_api.dart';

/// 신고·차단 고르기(편지 화면 메뉴, 두루마리 쪽지 길게 누르기)
Future<void> showSafetyMenu(
  BuildContext context, {
  required ReportTarget target,
  required String targetId,
  required String userId,
  required String nickname,
  VoidCallback? onBlocked,
}) => showModalBottomSheet<void>(
  context: context,
  backgroundColor: Palette.cream,
  showDragHandle: true,
  builder: (sheetContext) => SafeArea(
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        ListTile(
          key: const ValueKey('menu-report'),
          leading: const Icon(Icons.flag_rounded),
          title: Text(target == ReportTarget.user ? '$nickname님 신고하기' : '신고하기'),
          onTap: () {
            Navigator.pop(sheetContext);
            showReportSheet(
              context,
              target: target,
              targetId: targetId,
              nickname: nickname,
              userId: userId,
              onBlocked: onBlocked,
            );
          },
        ),
        ListTile(
          key: const ValueKey('menu-block'),
          leading: const Icon(Icons.block_rounded),
          title: Text('$nickname님 차단하기'),
          onTap: () async {
            Navigator.pop(sheetContext);
            await confirmBlock(context, userId: userId, nickname: nickname, onBlocked: onBlocked);
          },
        ),
        const SizedBox(height: 8),
      ],
    ),
  ),
);

/// 차단 확인 → 차단
Future<bool> confirmBlock(
  BuildContext context, {
  required String userId,
  required String nickname,
  VoidCallback? onBlocked,
}) async {
  final ok =
      await showDialog<bool>(
        context: context,
        builder: (c) => AlertDialog(
          title: Text('$nickname님을 차단할까요?'),
          content: const Text(
            '서로 편지를 주고받을 수 없고, 이 사람의 편지와 두루마리 글이 보이지 않아요. '
            '내 정보 > 설정에서 언제든 풀 수 있어요.',
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('취소')),
            TextButton(
              key: const ValueKey('confirm-block'),
              onPressed: () => Navigator.pop(c, true),
              child: const Text('차단'),
            ),
          ],
        ),
      ) ??
      false;
  if (!ok || !context.mounted) return false;
  final container = ProviderScope.containerOf(context, listen: false);
  try {
    await container.read(safetyApiProvider).block(userId);
    container.invalidate(blocksProvider);
    onBlocked?.call();
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$nickname님을 차단했어요.')));
    }
    return true;
  } on ApiException catch (e) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
    }
    return false;
  }
}

Future<void> showReportSheet(
  BuildContext context, {
  required ReportTarget target,
  required String targetId,
  required String userId,
  required String nickname,
  VoidCallback? onBlocked,
}) => showModalBottomSheet<void>(
  context: context,
  isScrollControlled: true,
  backgroundColor: Palette.cream,
  shape: const RoundedRectangleBorder(
    borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
  ),
  builder: (_) => ReportSheet(
    target: target,
    targetId: targetId,
    userId: userId,
    nickname: nickname,
    onBlocked: onBlocked,
  ),
);

class ReportSheet extends ConsumerStatefulWidget {
  const ReportSheet({
    super.key,
    required this.target,
    required this.targetId,
    required this.userId,
    required this.nickname,
    this.onBlocked,
  });

  final ReportTarget target;
  final String targetId;
  final String userId;
  final String nickname;
  final VoidCallback? onBlocked;

  @override
  ConsumerState<ReportSheet> createState() => _ReportSheetState();
}

class _ReportSheetState extends ConsumerState<ReportSheet> {
  String? _reason;
  final _detail = TextEditingController();
  bool _alsoBlock = false;
  bool _sending = false;
  String? _error;

  @override
  void dispose() {
    _detail.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    if (_reason == null) {
      setState(() => _error = '신고 이유를 골라 주세요.');
      return;
    }
    setState(() {
      _sending = true;
      _error = null;
    });
    final api = ref.read(safetyApiProvider);
    try {
      await api.report(
        target: widget.target,
        targetId: widget.targetId,
        reason: _reason!,
        detail: _detail.text,
      );
      if (_alsoBlock) {
        await api.block(widget.userId);
        ref.invalidate(blocksProvider);
        widget.onBlocked?.call();
      }
      if (!mounted) return;
      final messenger = ScaffoldMessenger.of(context);
      Navigator.pop(context);
      messenger.showSnackBar(
        SnackBar(content: Text(_alsoBlock ? '신고하고 차단했어요. 운영자가 확인할게요.' : '신고했어요. 운영자가 확인할게요.')),
      );
    } on ApiException catch (e) {
      if (mounted) {
        setState(() {
          _sending = false;
          _error = e.message;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) => Padding(
    padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
    child: SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(switch (widget.target) {
              ReportTarget.letter => '편지 신고하기',
              ReportTarget.rollingEntry => '두루마리 글 신고하기',
              ReportTarget.user => '${widget.nickname}님 신고하기',
            }, style: Theme.of(context).textTheme.headlineSmall),
            const SizedBox(height: 4),
            const Text(
              '신고는 상대에게 알려지지 않아요. 운영자가 확인하고 문제가 있으면 염소가 먹어 치워요.',
              style: TextStyle(fontSize: 13, height: 1.5),
            ),
            const SizedBox(height: 10),
            RadioGroup<String>(
              groupValue: _reason,
              onChanged: (v) => setState(() => _reason = v),
              child: Column(
                children: [
                  for (final (code, label) in reportReasons)
                    RadioListTile<String>(
                      key: ValueKey('reason-$code'),
                      value: code,
                      title: Text(label),
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                    ),
                ],
              ),
            ),
            TextField(
              key: const ValueKey('report-detail'),
              controller: _detail,
              maxLength: 500,
              maxLines: 3,
              minLines: 1,
              decoration: const InputDecoration(
                hintText: '더 알려 줄 내용(선택)',
                filled: true,
                fillColor: Colors.white,
                border: OutlineInputBorder(),
              ),
            ),
            CheckboxListTile(
              key: const ValueKey('also-block'),
              value: _alsoBlock,
              onChanged: (v) => setState(() => _alsoBlock = v ?? false),
              title: Text('${widget.nickname}님도 차단하기'),
              contentPadding: EdgeInsets.zero,
              controlAffinity: ListTileControlAffinity.leading,
            ),
            if (_error != null) ...[NoticeBox(_error!), const SizedBox(height: 10)],
            ChunkyButton(
              key: const ValueKey('send-report'),
              label: '신고하기',
              color: Palette.pink,
              loading: _sending,
              onPressed: _sending ? null : _send,
            ),
          ],
        ),
      ),
    ),
  );
}
