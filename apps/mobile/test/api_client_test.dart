import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:meeil/core/api_client.dart';
import 'package:meeil/core/token_store.dart';

/// 경로별 응답을 흉내 내는 어댑터. 요청 기록을 남긴다.
class FakeAdapter implements HttpClientAdapter {
  FakeAdapter(this.handler);

  final ResponseBody Function(RequestOptions options) handler;
  final requests = <RequestOptions>[];

  @override
  Future<ResponseBody> fetch(RequestOptions options, Stream<Uint8List>? _, Future<void>? _) async {
    requests.add(options);
    return handler(options);
  }

  @override
  void close({bool force = false}) {}
}

ResponseBody json(int status, Object body) => ResponseBody.fromString(
  jsonEncode(body),
  status,
  headers: {
    Headers.contentTypeHeader: ['application/json'],
  },
);

ApiClient client(MemoryTokenStore store, FakeAdapter adapter) {
  final c = ApiClient(baseUrl: 'http://api.test', tokenStore: store);
  c.dio.httpClientAdapter = adapter;
  return c;
}

void main() {
  test('401이면 refresh 후 새 토큰으로 한 번 재시도한다', () async {
    final store = MemoryTokenStore()..tokens = const Tokens(accessToken: 'old', refreshToken: 'r1');
    final adapter = FakeAdapter((o) {
      if (o.path == '/auth/refresh') {
        expect(o.headers['Authorization'], isNull, reason: 'refresh에는 access 토큰을 붙이지 않는다');
        return json(200, {'accessToken': 'new', 'refreshToken': 'r2'});
      }
      return o.headers['Authorization'] == 'Bearer new'
          ? json(200, {'ok': true})
          : json(401, {
              'error': {'code': 'UNAUTHORIZED', 'message': '다시 로그인해 주세요.'},
            });
    });
    final res = await client(store, adapter).get('/me');
    expect(res, {'ok': true});
    expect(store.tokens!.accessToken, 'new');
    expect(store.tokens!.refreshToken, 'r2');
    expect(adapter.requests.map((r) => r.path), ['/me', '/auth/refresh', '/me']);
  });

  test('refresh도 실패하면 토큰을 지우고 세션 만료를 알린다', () async {
    final store = MemoryTokenStore()..tokens = const Tokens(accessToken: 'old', refreshToken: 'r1');
    var expired = false;
    final adapter = FakeAdapter(
      (o) => json(401, {
        'error': {'code': 'UNAUTHORIZED', 'message': '다시 로그인해 주세요.'},
      }),
    );
    final c = client(store, adapter)..onSessionExpired = () => expired = true;
    await expectLater(
      c.get('/me'),
      throwsA(isA<ApiException>().having((e) => e.statusCode, 'status', 401)),
    );
    expect(store.tokens, isNull);
    expect(expired, isTrue);
  });

  test('서버 오류 문구를 그대로 전달하고, 응답이 없으면 네트워크 오류', () async {
    final store = MemoryTokenStore();
    final adapter = FakeAdapter(
      (o) => json(409, {
        'error': {'code': 'NICKNAME_TAKEN', 'message': '이미 누군가 쓰고 있는 닉네임이에요.'},
      }),
    );
    await expectLater(
      client(store, adapter).put('/me/nickname', {'nickname': 'x'}),
      throwsA(
        isA<ApiException>()
            .having((e) => e.code, 'code', 'NICKNAME_TAKEN')
            .having((e) => e.message, 'message', '이미 누군가 쓰고 있는 닉네임이에요.'),
      ),
    );

    final offline = client(
      store,
      FakeAdapter((o) => throw DioException.connectionError(requestOptions: o, reason: 'offline')),
    );
    await expectLater(
      offline.get('/me'),
      throwsA(isA<ApiException>().having((e) => e.code, 'code', 'NETWORK')),
    );
  });
}
