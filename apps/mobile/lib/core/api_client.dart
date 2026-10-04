import 'dart:async';

import 'package:dio/dio.dart';

import 'token_store.dart';

/// 서버 오류. [message]는 서버가 준 한국어 문구(사용자에게 그대로 보여준다).
class ApiException implements Exception {
  const ApiException(this.code, this.message, {this.statusCode});

  final String code;
  final String message;
  final int? statusCode;

  static const network = ApiException('NETWORK', '인터넷 연결을 확인해 주세요.');

  @override
  String toString() => 'ApiException($code, $message)';
}

/// dio 래퍼. access 토큰을 붙이고, 401이면 refresh로 한 번 갱신 후 재시도한다.
class ApiClient {
  ApiClient({required String baseUrl, required this.tokenStore, Dio? dio, this.onSessionExpired})
    : dio =
          dio ??
          Dio(
            BaseOptions(
              baseUrl: baseUrl,
              connectTimeout: const Duration(seconds: 10),
              receiveTimeout: const Duration(seconds: 15),
              contentType: 'application/json',
            ),
          ) {
    this.dio.interceptors.add(
      QueuedInterceptorsWrapper(
        onRequest: (options, handler) async {
          if (options.extra['auth'] != false) {
            final tokens = await tokenStore.read();
            if (tokens != null) options.headers['Authorization'] = 'Bearer ${tokens.accessToken}';
          }
          handler.next(options);
        },
        onError: (err, handler) async {
          final opts = err.requestOptions;
          final canRetry =
              err.response?.statusCode == 401 &&
              opts.extra['auth'] != false &&
              opts.extra['retried'] != true;
          if (!canRetry) return handler.next(err);
          final refreshed = await _refresh();
          if (!refreshed) {
            await tokenStore.clear();
            onSessionExpired?.call();
            return handler.next(err);
          }
          try {
            final tokens = await tokenStore.read();
            opts.extra['retried'] = true;
            opts.headers['Authorization'] = 'Bearer ${tokens!.accessToken}';
            handler.resolve(await this.dio.fetch(opts));
          } on DioException catch (e) {
            handler.next(e);
          }
        },
      ),
    );
  }

  final Dio dio;
  final TokenStore tokenStore;

  /// refresh까지 실패해 로그아웃 처리해야 할 때
  void Function()? onSessionExpired;

  /// refresh 전용 Dio(인터셉터 없음). 같은 큐 인터셉터를 다시 타면 refresh 실패 시 교착된다.
  Dio get _refreshDio {
    final d = Dio(dio.options.copyWith());
    d.httpClientAdapter = dio.httpClientAdapter;
    return d;
  }

  Future<bool> _refresh() async {
    final tokens = await tokenStore.read();
    if (tokens == null) return false;
    try {
      final res = await _refreshDio.post<Map<String, dynamic>>(
        '/auth/refresh',
        data: {'refreshToken': tokens.refreshToken},
      );
      final body = res.data!;
      await tokenStore.write(
        Tokens(
          accessToken: body['accessToken'] as String,
          refreshToken: body['refreshToken'] as String,
        ),
      );
      return true;
    } on DioException {
      return false;
    }
  }

  Future<Map<String, dynamic>> get(String path, {Map<String, dynamic>? query}) =>
      _send(() => dio.get<Map<String, dynamic>>(path, queryParameters: query));

  Future<Map<String, dynamic>> post(String path, Object? body, {bool auth = true}) => _send(
    () => dio.post<Map<String, dynamic>>(
      path,
      data: body,
      options: Options(extra: {'auth': auth}),
    ),
  );

  Future<Map<String, dynamic>> postForm(String path, FormData form) => _send(
    () => dio.post<Map<String, dynamic>>(
      path,
      data: form,
      options: Options(sendTimeout: const Duration(seconds: 60)),
    ),
  );

  Future<void> delete(String path) async {
    try {
      await dio.delete<void>(path);
    } on DioException catch (e) {
      throw toApiException(e);
    }
  }

  Future<Map<String, dynamic>> put(String path, Object? body) =>
      _send(() => dio.put<Map<String, dynamic>>(path, data: body));

  Future<Map<String, dynamic>> _send(Future<Response<Map<String, dynamic>>> Function() call) async {
    try {
      final res = await call();
      return res.data ?? const {};
    } on DioException catch (e) {
      throw toApiException(e);
    }
  }

  static ApiException toApiException(DioException e) {
    final data = e.response?.data;
    if (data is Map && data['error'] is Map) {
      final err = data['error'] as Map;
      return ApiException(
        err['code'] as String? ?? 'UNKNOWN',
        err['message'] as String? ?? '문제가 생겼어요.',
        statusCode: e.response?.statusCode,
      );
    }
    if (e.response == null) return ApiException.network;
    return ApiException(
      'HTTP_${e.response!.statusCode}',
      '문제가 생겼어요. 잠시 후 다시 시도해 주세요.',
      statusCode: e.response!.statusCode,
    );
  }
}
