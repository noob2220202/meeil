import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/theme.dart';
import '../../core/api_client.dart';
import '../../ui/widgets.dart';
import '../auth/session.dart';
import 'terms_screen.dart' show signupSteps;

String formatBirthDate(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

class BirthScreen extends ConsumerStatefulWidget {
  const BirthScreen({super.key});

  @override
  ConsumerState<BirthScreen> createState() => _BirthScreenState();
}

class _BirthScreenState extends ConsumerState<BirthScreen> {
  DateTime _date = DateTime(2005, 1, 1);
  bool _busy = false;
  String? _error;

  Future<void> _submit() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('생년월일 확인'),
        content: Text('${_date.year}년 ${_date.month}월 ${_date.day}일이 맞나요?\n생년월일은 나중에 바꿀 수 없어요.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('다시 고를게요')),
          TextButton(onPressed: () => Navigator.pop(context, true), child: const Text('맞아요')),
        ],
      ),
    );
    if (ok != true) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final me = await ref.read(authApiProvider).setBirthDate(formatBirthDate(_date));
      ref.read(sessionProvider.notifier).update(me);
    } on ApiException catch (e) {
      if (e.code == 'UNDER_AGE') {
        await ref.read(sessionProvider.notifier).rejectUnderAge();
        return;
      }
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    return StepScaffold(
      step: 2,
      totalSteps: signupSteps,
      title: '생일이 언제예요?',
      subtitle: '만 14세 이상만 가입할 수 있어요.\n생년월일은 다른 사람에게 절대 보이지 않아요.',
      bottom: Column(
        children: [
          if (_error != null) ...[NoticeBox(_error!), const SizedBox(height: 12)],
          ChunkyButton(label: '다음', color: Palette.yellow, loading: _busy, onPressed: _submit),
        ],
      ),
      child: Align(
        alignment: Alignment.topCenter,
        child: Container(
          height: 220,
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: Palette.outline, width: 2.5),
          ),
          clipBehavior: Clip.antiAlias,
          child: CupertinoTheme(
            data: const CupertinoThemeData(
              textTheme: CupertinoTextThemeData(
                dateTimePickerTextStyle: TextStyle(
                  fontFamily: Fonts.body,
                  fontSize: 21,
                  color: Palette.textBrown,
                ),
              ),
            ),
            child: CupertinoDatePicker(
              mode: CupertinoDatePickerMode.date,
              dateOrder: DatePickerDateOrder.ymd,
              initialDateTime: _date,
              minimumDate: DateTime(1900),
              maximumDate: DateTime(now.year, now.month, now.day),
              onDateTimeChanged: (d) => _date = d,
            ),
          ),
        ),
      ),
    );
  }
}
