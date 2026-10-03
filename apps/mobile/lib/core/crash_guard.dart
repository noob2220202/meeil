import 'dart:async';
import 'dart:collection';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../app/theme.dart';
import 'config.dart';

/// 앱이 죽지 않게 하는 마지막 그물 (M7 "크래시 없음").
/// - 프레임워크·비동기 오류를 잡아 기록하고, 운영 빌드에서는 서버로 요약만 보낸다(개인정보 없음).
/// - 위젯 하나가 그리다 실패해도 빨간 화면 대신 귀여운 안내 카드를 보여 준다.
class CrashGuard {
  CrashGuard({ErrorReporter? reporter}) : reporter = reporter ?? ErrorReporter();

  final ErrorReporter reporter;

  void install() {
    final previous = FlutterError.onError;
    FlutterError.onError = (details) {
      previous?.call(details);
      reporter.report(details.exception, details.stack, source: details.library);
    };
    PlatformDispatcher.instance.onError = (error, stack) {
      reporter.report(error, stack, source: 'platform');
      return true; // 처리했으니 앱을 끝내지 않는다
    };
    if (kReleaseMode) ErrorWidget.builder = (details) => const BrokenPiece();
  }
}

/// 같은 오류는 한 번만, 1분에 최대 5건만 보낸다
class ErrorReporter {
  ErrorReporter({Dio? dio, this.enabled = kReleaseMode})
    : _dio =
          dio ??
          Dio(
            BaseOptions(baseUrl: AppConfig.apiBaseUrl, connectTimeout: const Duration(seconds: 5)),
          );

  final Dio _dio;
  final bool enabled;
  final _seen = HashSet<String>();
  final _sentAt = <DateTime>[];

  @visibleForTesting
  final sent = <Map<String, Object?>>[];

  void report(Object error, StackTrace? stack, {String? source}) {
    final message = _trim(error.toString(), 500);
    final top = _trim((stack ?? StackTrace.empty).toString(), 4000);
    final key = '$message|${top.split('\n').take(3).join()}';
    if (!_seen.add(key)) return;
    final now = DateTime.now();
    _sentAt.removeWhere((t) => now.difference(t) > const Duration(minutes: 1));
    if (_sentAt.length >= 5) return;
    _sentAt.add(now);
    final body = <String, Object?>{
      'message': message,
      'stack': top,
      'source': source,
      'platform': defaultTargetPlatform.name,
      'mode': kReleaseMode ? 'release' : (kProfileMode ? 'profile' : 'debug'),
    };
    sent.add(body);
    if (!enabled) return;
    unawaited(_dio.post<void>('/client-errors', data: body).then((_) {}, onError: (_) {}));
  }

  static String _trim(String s, int max) => s.length <= max ? s : s.substring(0, max);
}

/// 그리다 넘어진 자리에 보여 주는 카드
class BrokenPiece extends StatelessWidget {
  const BrokenPiece({super.key});

  @override
  Widget build(BuildContext context) => Directionality(
    textDirection: TextDirection.ltr,
    child: Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Palette.cream,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Palette.outline, width: 2),
      ),
      child: const Text(
        '앗, 염소가 여기를 그리다 넘어졌어요.\n잠시 뒤 다시 열어 주세요.',
        textAlign: TextAlign.center,
        style: TextStyle(color: Palette.textBrown, fontSize: 14, height: 1.5),
      ),
    ),
  );
}
