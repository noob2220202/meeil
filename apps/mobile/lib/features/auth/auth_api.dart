import '../../core/api_client.dart';
import '../../core/token_store.dart';
import 'me.dart';

class LoginResult {
  const LoginResult(this.tokens, this.me, {required this.isNew});

  final Tokens tokens;
  final Me me;
  final bool isNew;
}

class NicknameCheck {
  const NicknameCheck({required this.available, required this.message});

  final bool available;
  final String message;
}

enum SocialProvider { kakao, google, dev }

/// 인증·가입 API
class AuthApi {
  AuthApi(this.client);

  final ApiClient client;

  Future<LoginResult> login(SocialProvider provider, String token) async {
    final (path, body) = switch (provider) {
      SocialProvider.kakao => ('/auth/kakao', {'accessToken': token}),
      SocialProvider.google => ('/auth/google', {'idToken': token}),
      SocialProvider.dev => ('/auth/dev', {'devId': token}),
    };
    final j = await client.post(path, body, auth: false);
    return LoginResult(
      Tokens(accessToken: j['accessToken'] as String, refreshToken: j['refreshToken'] as String),
      Me.fromJson(j['me'] as Map<String, dynamic>),
      isNew: j['isNew'] as bool,
    );
  }

  Future<void> logout(String refreshToken) async {
    try {
      await client.post('/auth/logout', {'refreshToken': refreshToken}, auth: false);
    } on ApiException {
      // 로그아웃은 기기에서 토큰을 지우는 것이 핵심이므로 서버 실패는 무시한다
    }
  }

  Future<Me> me() async => Me.fromJson(await client.get('/me'));

  Future<Me> agree() async =>
      Me.fromJson(await client.post('/me/agreements', {'terms': true, 'privacy': true}));

  /// [birthDate]는 'YYYY-MM-DD'
  Future<Me> setBirthDate(String birthDate) async =>
      Me.fromJson(await client.post('/me/birthdate', {'birthDate': birthDate}));

  Future<NicknameCheck> checkNickname(String nick) async {
    final j = await client.get('/nicknames/check', query: {'nick': nick});
    return NicknameCheck(available: j['available'] as bool, message: j['message'] as String);
  }

  Future<Me> setNickname(String nick) async =>
      Me.fromJson(await client.put('/me/nickname', {'nickname': nick}));
}
