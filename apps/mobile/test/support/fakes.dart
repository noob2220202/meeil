import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:meeil/core/api_client.dart';
import 'package:meeil/core/app_flags.dart';
import 'package:meeil/core/token_store.dart';
import 'package:meeil/data/regions.dart';
import 'package:meeil/features/auth/auth_api.dart';
import 'package:meeil/features/auth/me.dart';
import 'package:meeil/features/auth/session.dart';
import 'package:meeil/features/auth/social_login.dart';
import 'package:meeil/features/onboarding/permissions_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _FakeUser {
  _FakeUser(this.id);

  final String id;
  bool terms = false;
  bool birth = false;
  String? nickname;
  int points = 0;

  Me toMe() => Me(
    id: id,
    nickname: nickname,
    status: 'ACTIVE',
    pointsBalance: points,
    termsAgreed: terms,
    birthDateSet: birth,
    nicknameSet: nickname != null,
  );
}

/// 서버 규칙을 흉내 내는 메모리 백엔드(테스트용)
class FakeBackend {
  final _byProvider = <String, _FakeUser>{};
  final _byId = <String, _FakeUser>{};
  bool forceUnderAge = false;
  bool offline = false;
  final takenNicknames = <String>{'메롱이'};
  int _seq = 0;

  _FakeUser _user(String accessToken) {
    if (offline) throw ApiException.network;
    final u = _byId[accessToken.replaceFirst('access:', '')];
    if (u == null) throw const ApiException('UNAUTHORIZED', '다시 로그인해 주세요.', statusCode: 401);
    return u;
  }

  void _complete(_FakeUser u) {
    if (u.terms && u.birth && u.nickname != null && u.points == 0) u.points = 5;
  }
}

class FakeAuthApi extends AuthApi {
  FakeAuthApi(this.backend, this.store)
    : super(ApiClient(baseUrl: 'http://fake.invalid', tokenStore: store));

  final FakeBackend backend;
  final TokenStore store;

  Future<_FakeUser> _current() async => backend._user((await store.read())?.accessToken ?? '');

  @override
  Future<LoginResult> login(SocialProvider provider, String token) async {
    final key = '${provider.name}:$token';
    final user = backend._byProvider.putIfAbsent(key, () {
      final u = _FakeUser('u${++backend._seq}');
      backend._byId[u.id] = u;
      return u;
    });
    return LoginResult(
      Tokens(accessToken: 'access:${user.id}', refreshToken: 'refresh:${user.id}'),
      user.toMe(),
      isNew: true,
    );
  }

  @override
  Future<void> logout(String refreshToken) async {}

  @override
  Future<Me> me() async => (await _current()).toMe();

  @override
  Future<Me> agree() async {
    final u = await _current();
    u.terms = true;
    backend._complete(u);
    return u.toMe();
  }

  @override
  Future<Me> setBirthDate(String birthDate) async {
    final u = await _current();
    if (backend.forceUnderAge) {
      backend._byId.remove(u.id);
      backend._byProvider.removeWhere((_, v) => v == u);
      throw const ApiException('UNDER_AGE', '메에일은 만 14세 이상부터 이용할 수 있어요.', statusCode: 403);
    }
    u.birth = true;
    backend._complete(u);
    return u.toMe();
  }

  @override
  Future<NicknameCheck> checkNickname(String nick) async {
    await _current();
    if (backend.takenNicknames.contains(nick)) {
      return const NicknameCheck(available: false, message: '이미 누군가 쓰고 있는 닉네임이에요.');
    }
    return const NicknameCheck(available: true, message: '멋진 닉네임이에요!');
  }

  @override
  Future<Me> setNickname(String nick) async {
    final u = await _current();
    u.nickname = nick;
    backend.takenNicknames.add(nick);
    backend._complete(u);
    return u.toMe();
  }
}

class FakeSocialLogin implements SocialLogin {
  String? kakaoToken = 'kakao-user-1';
  String? googleToken = 'google-user-1';

  @override
  Future<String?> kakaoAccessToken() async => kakaoToken;

  @override
  Future<String?> googleIdToken() async => googleToken;

  @override
  Future<void> signOutAll() async {}
}

class FakePermissions implements PermissionGateway {
  int locationRequests = 0;
  int notificationRequests = 0;

  @override
  Future<bool> requestLocation() async {
    locationRequests++;
    return true;
  }

  @override
  Future<bool> requestNotification() async {
    notificationRequests++;
    return true;
  }
}

/// 앱 한 번 실행에 해당하는 provider override 묶음. 같은 store/prefs를 넘기면 "재실행"이 된다.
Future<List<Override>> appOverrides({
  required FakeBackend backend,
  required MemoryTokenStore store,
  FakeSocialLogin? social,
  FakePermissions? permissions,
}) async {
  final prefs = await SharedPreferences.getInstance();
  return [
    sharedPrefsProvider.overrideWithValue(prefs),
    tokenStoreProvider.overrideWithValue(store),
    authApiProvider.overrideWithValue(FakeAuthApi(backend, store)),
    socialLoginProvider.overrideWithValue(social ?? FakeSocialLogin()),
    permissionGatewayProvider.overrideWithValue(permissions ?? FakePermissions()),
    regionDataProvider.overrideWith(
      (ref) async => RegionData(version: 'test', provinces: const [], regions: const []),
    ),
  ];
}
