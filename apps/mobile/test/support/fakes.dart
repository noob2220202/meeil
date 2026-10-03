import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:meeil/core/api_client.dart';
import 'package:meeil/core/app_flags.dart';
import 'package:meeil/core/token_store.dart';
import 'package:meeil/data/regions.dart';
import 'package:meeil/features/auth/auth_api.dart';
import 'package:meeil/features/auth/me.dart';
import 'package:meeil/features/auth/session.dart';
import 'package:meeil/features/auth/social_login.dart';
import 'package:meeil/features/goats/goats_api.dart';
import 'package:meeil/features/goats/schedule.dart';
import 'package:meeil/features/location/my_region.dart';
import 'package:meeil/features/onboarding/permissions_screen.dart';

import 'dart:convert';
import 'dart:io';

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
  LocationSource? location,
  RegionApi? regionApi,
  bool scheduleFails = false,
}) async {
  final prefs = await SharedPreferences.getInstance();
  return [
    sharedPrefsProvider.overrideWithValue(prefs),
    tokenStoreProvider.overrideWithValue(store),
    authApiProvider.overrideWithValue(FakeAuthApi(backend, store)),
    socialLoginProvider.overrideWithValue(social ?? FakeSocialLogin()),
    permissionGatewayProvider.overrideWithValue(permissions ?? FakePermissions()),
    // compute()·실제 파일 로딩은 가짜 시간에서 끝나지 않으므로 미리 파싱한 값을 쓴다
    regionDataProvider.overrideWith((ref) async => testRegionData),
    goatsApiProvider.overrideWithValue(FakeGoatsApi(store, fail: scheduleFails)),
    regionApiProvider.overrideWithValue(regionApi ?? FakeRegionApi(store)),
    locationSourceProvider.overrideWithValue(
      location ?? FakeLocationSource(grant: LocationAccess.denied),
    ),
  ];
}

/// 실제 서버 생성기로 만든 2026-10-03 12:00 KST 스케줄(tools/schedule-sim fixture)
const scheduleFixturePath = 'test/fixtures/schedule_20261003_1200kst.json';
final fixtureNow = DateTime.utc(2026, 10, 3, 3);

GoatSchedule loadScheduleFixture() {
  final j = jsonDecode(File(scheduleFixturePath).readAsStringSync()) as Map<String, dynamic>;
  // 기기 시계 = 서버 시계로 맞춘다(오프셋 0)
  final t = DateTime.parse(j['serverTime'] as String);
  return GoatSchedule.fromJson(j, requestStarted: t, responseReceived: t);
}

class FakeGoatsApi extends GoatsApi {
  FakeGoatsApi(MemoryTokenStore store, {this.fail = false})
    : super(ApiClient(baseUrl: 'http://fake.invalid', tokenStore: store));

  final bool fail;

  @override
  Future<GoatSchedule> fetchSchedule({int hours = 48}) async {
    if (fail) throw ApiException.network;
    return loadScheduleFixture();
  }
}

/// 서버 판정을 흉내 낸다: 가짜 위치는 거부
class FakeRegionApi extends RegionApi {
  FakeRegionApi(MemoryTokenStore store)
    : super(ApiClient(baseUrl: 'http://fake.invalid', tokenStore: store));

  final reports = <String>[];

  @override
  Future<RegionReport> report(String regionCode, {required bool mocked}) async {
    reports.add(regionCode);
    return mocked
        ? const RegionReport(accepted: false)
        : RegionReport(accepted: true, regionCode: regionCode);
  }
}

class FakeLocationSource implements LocationSource {
  FakeLocationSource({this.fix, this.grant = LocationAccess.granted});

  LocationFix? fix;
  LocationAccess grant;

  @override
  Future<LocationAccess> access() async => grant;

  @override
  Future<LocationAccess> requestAccess() async => grant;

  @override
  Future<LocationFix?> currentFix() async => fix;

  @override
  Future<void> openSettings() async {}
}

/// 번들 지역 데이터(테스트에서 한 번만 파싱)
final testRegionData = RegionData.parse(File(regionAssetPath).readAsStringSync());
