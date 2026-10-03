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
import 'package:meeil/features/goats/hand_availability.dart';
import 'package:flutter/painting.dart';
import 'package:meeil/features/letters/letter_models.dart';
import 'package:meeil/features/map/goat_painter.dart';
import 'package:meeil/features/letters/letters_api.dart';
import 'package:meeil/features/goats/schedule.dart';
import 'package:meeil/features/location/my_region.dart';
import 'package:meeil/features/onboarding/permissions_screen.dart';
import 'package:meeil/features/letters/compose_controller.dart';
import 'package:meeil/features/rewards/ad_gateway.dart';
import 'package:meeil/features/rewards/rewards_api.dart';
import 'package:meeil/features/rewards/rewards_models.dart';
import 'package:meeil/features/rolling/rolling_api.dart';
import 'package:meeil/features/safety/safety_api.dart';
import 'package:meeil/features/rolling/rolling_models.dart';

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
  String? title;
  String? titleId;
  bool randomReceive = true;
  bool notifyEnabled = true;

  Me toMe() => Me(
    randomReceive: randomReceive,
    notifyEnabled: notifyEnabled,
    title: title,
    titleAchievementId: titleId,
    adsUnderAge: false,
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

  /// 가입을 마친 사용자를 바로 만든다(로그인된 앱으로 시작할 때)
  Tokens signedUp(String nickname, {int points = 5}) {
    final u = _FakeUser('u${++_seq}')
      ..terms = true
      ..birth = true
      ..nickname = nickname
      ..points = points;
    _byId[u.id] = u;
    return Tokens(accessToken: 'access:${u.id}', refreshToken: 'refresh:${u.id}');
  }

  int pointsOf(Tokens t) => _user(t.accessToken).points;

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
  FakeLettersApi? letters,
  FakeRollingApi? rolling,
  FakeRewardsApi? rewards,
  FakeAdGateway? ads,
  FakeSafetyApi? safety,
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
    lettersApiProvider.overrideWithValue(letters ?? FakeLettersApi(store)),
    rollingApiProvider.overrideWithValue(rolling ?? FakeRollingApi(store)),
    rewardsApiProvider.overrideWithValue(rewards ?? FakeRewardsApi(backend, store)),
    adGatewayProvider.overrideWithValue(ads ?? FakeAdGateway()),
    safetyApiProvider.overrideWithValue(safety ?? FakeSafetyApi(store, backend: backend)),
    stationeryProvider.overrideWith(
      (ref) async => (rewards ?? FakeRewardsApi(backend, store)).stationery(),
    ),
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

/// 메모리 편지함(서버 규칙 중 화면에 필요한 부분만)
class FakeLettersApi extends LettersApi {
  FakeLettersApi(MemoryTokenStore store)
    : super(ApiClient(baseUrl: 'http://fake.invalid', tokenStore: store));

  final inbox = <Letter>[];
  final sent = <Letter>[];
  final trashed = <Letter>[];
  final handed = <HandRequest>[];
  final users = <Person>[
    const Person(id: 'u-dubu', nickname: '두부염소'),
    const Person(id: 'u-kong', nickname: '콩이네', title: '단골 손님'),
  ];
  ApiException? handError;
  int uploads = 0;

  @override
  Future<Letter> hand(HandRequest req) async {
    if (handError != null) throw handError!;
    handed.add(req);
    final l = Letter(
      id: 'sent-${sent.length + 1}',
      mode: req.mode,
      isSender: true,
      status: LetterStatus.inTransit,
      sender: const Person(id: 'me', nickname: '나'),
      recipient: req.mode == LetterMode.random
          ? null
          : users.firstWhere((u) => u.id == req.recipientId, orElse: () => users.first),
      body: req.body,
      stationeryId: req.stationeryId,
      stickers: req.stickers,
      photo: null,
      handedAt: fixtureNow,
      etaAt: fixtureNow.add(const Duration(hours: 9, minutes: 20)),
      goatId: 'merongi',
      goatName: '메롱이',
    );
    sent.insert(0, l);
    return l;
  }

  @override
  Future<LetterPage> list(MailBox box, {String? cursor}) async => LetterPage(switch (box) {
    MailBox.inbox => inbox,
    MailBox.sent => sent,
    MailBox.trash => trashed,
  }, null);

  @override
  Future<int> unreadCount() async => inbox.where((l) => l.isUnread).length;

  @override
  Future<Letter> get(String id) async =>
      [...inbox, ...sent, ...trashed].firstWhere((l) => l.id == id);

  @override
  Future<Letter> markRead(String id) async {
    final i = inbox.indexWhere((l) => l.id == id);
    final l = inbox[i];
    final read = Letter(
      id: l.id,
      mode: l.mode,
      isSender: false,
      status: LetterStatus.read,
      sender: l.sender,
      recipient: l.recipient,
      body: l.body,
      stationeryId: l.stationeryId,
      stickers: l.stickers,
      photo: l.photo,
      handedAt: l.handedAt,
      deliveredAt: l.deliveredAt,
      readAt: fixtureNow,
      goatId: l.goatId,
      goatName: l.goatName,
      canReply: true,
    );
    inbox[i] = read;
    return read;
  }

  @override
  Future<List<Person>> searchUsers(String nick) async =>
      users.where((u) => u.nickname.startsWith(nick)).toList();

  @override
  Future<String> uploadPhoto(String path) async {
    uploads++;
    return 'photo-$uploads';
  }
}

/// 받은 편지 예시
Letter sampleReceived({
  String id = 'in-1',
  bool unread = true,
  String stationeryId = 'cream',
  LetterMode mode = LetterMode.direct,
  String body = '오늘 우리 동네에 메롱이가 왔어! 너한테도 염소가 놀러 가길 바라며 편지 보내.',
  bool eaten = false,
}) => Letter(
  id: id,
  mode: mode,
  isSender: false,
  status: eaten
      ? LetterStatus.eaten
      : unread
      ? LetterStatus.delivered
      : LetterStatus.read,
  sender: const Person(id: 'u-dubu', nickname: '두부염소', title: '단골 손님'),
  recipient: const Person(id: 'me', nickname: '나'),
  body: body,
  stationeryId: stationeryId,
  stickers: const [PlacedSticker('heart', 0.9, 0.05), PlacedSticker('goat-love', 0.05, 0.92)],
  photo: null,
  handedAt: fixtureNow.subtract(const Duration(hours: 20)),
  deliveredAt: fixtureNow.subtract(const Duration(hours: 1)),
  goatId: 'merongi',
  goatName: '메롱이',
  goatLook: const GoatLook(hat: Color(0xFFE8505B), bag: Color(0xFFF6C177)),
  canReply: true,
  originRegionCode: '11110',
);

/// 테스트용 고정 시계
class FixedClock extends ClockTick {
  FixedClock(this.at);
  final DateTime at;

  @override
  DateTime build() => at;
}

/// 롤링페이퍼 가짜 서버. 레벨별 이번 장 하나씩 + 앨범.
class FakeRollingApi extends RollingApi {
  FakeRollingApi(MemoryTokenStore store, {DateTime? now})
    : now = now ?? fixtureNow,
      super(ApiClient(baseUrl: 'http://fake.invalid', tokenStore: store));

  final DateTime now;
  final views = <RollingLevel, RollingView>{};
  final errors = <RollingLevel, String>{};
  final album_ = <RollingPaper>[];
  final closed = <String, RollingView>{};
  final joins = <(String, String, List<PlacedSticker>)>[];
  ApiException? joinError;
  bool fail = false;

  static RollingPaper paper(
    RollingLevel level, {
    String? id,
    String scopeName = '서울 종로구',
    String? topic,
    DateTime? start,
    DateTime? end,
    int? entryCount,
  }) => RollingPaper(
    id: id ?? 'paper-${level.api.toLowerCase()}',
    level: level,
    scopeCode: level == RollingLevel.nation ? 'KR' : '11110',
    scopeName: scopeName,
    topic: topic,
    periodStart: start ?? DateTime.utc(2026, 10, 2, 15),
    periodEnd: end ?? DateTime.utc(2026, 10, 3, 15),
    goatName: '분홍이',
    entryCount: entryCount,
  );

  static RollingView view(
    RollingPaper p, {
    List<RollingEntry> entries = const [],
    bool canJoin = false,
    bool joined = false,
    JoinBlock? block,
    DateTime? next,
    bool closed = false,
  }) => RollingView(
    paper: p,
    entries: entries,
    entryCount: entries.length,
    joined: joined,
    canJoin: canJoin,
    joinBlock: block,
    goatHere: canJoin,
    goatNextArriveAt: next,
    closed: closed,
  );

  RollingView? _byId(String id) =>
      closed[id] ?? views.values.where((v) => v.paper.id == id).firstOrNull;

  @override
  Future<RollingSummary> summary() async {
    if (fail) throw const ApiException('NETWORK', '연결이 불안정해요.');
    return RollingSummary(Map.of(views), Map.of(errors));
  }

  @override
  Future<RollingView> current(RollingLevel level) async => views[level]!;

  @override
  Future<RollingView> get(String id) async {
    final v = _byId(id);
    if (v == null) throw const ApiException('PAPER_NOT_FOUND', '두루마리를 찾을 수 없어요.', statusCode: 404);
    return v;
  }

  @override
  Future<RollingEntry> join(String paperId, String body, List<PlacedSticker> stickers) async {
    if (joinError != null) throw joinError!;
    joins.add((paperId, body, stickers));
    final e = RollingEntry(
      id: 'entry-${joins.length}',
      author: const Person(id: 'me', nickname: '나', title: '새내기 우체부'),
      body: body,
      stickers: stickers,
      mine: true,
      createdAt: now,
    );
    for (final key in views.keys.toList()) {
      if (views[key]!.paper.id == paperId) views[key] = views[key]!.withEntry(e);
    }
    return e;
  }

  @override
  Future<List<RollingPaper>> album() async => List.of(album_);
}

RollingEntry sampleEntry(
  String id,
  String nickname,
  String body, {
  String? title,
  List<PlacedSticker> stickers = const [],
  bool mine = false,
}) => RollingEntry(
  id: id,
  author: Person(id: 'u-$id', nickname: nickname, title: title),
  body: body,
  stickers: stickers,
  mine: mine,
  createdAt: fixtureNow.subtract(const Duration(hours: 2)),
);

/// 보상 가짜 서버: 출석·광고·업적. 포인트는 FakeBackend의 사용자에게 더한다.
class FakeRewardsApi extends RewardsApi {
  FakeRewardsApi(this.backend, this.store, {this.today = '2026-10-03'})
    : super(ApiClient(baseUrl: 'http://fake.invalid', tokenStore: store));

  final FakeBackend backend;
  final MemoryTokenStore store;
  String today;
  final days = <String>{};
  int streak = 0;
  int adToday = 0;
  final ledger = <LedgerEntry>[];
  final pending = <Achievement>[];
  final seen = <String>[];
  List<Achievement> book = sampleAchievements();
  final owned = <String>{'cream'};
  bool fail = false;

  Future<_FakeUser> _me() async => backend._user((await store.read())?.accessToken ?? '');

  Future<void> _give(int delta, String reason, String label) async {
    final u = await _me();
    u.points += delta;
    ledger.insert(
      0,
      LedgerEntry(
        id: 'l${ledger.length}',
        delta: delta,
        balanceAfter: u.points,
        reason: reason,
        label: label,
        createdAt: fixtureNow,
      ),
    );
  }

  AttendanceStatus _status({bool justChecked = false, int earned = 0}) => AttendanceStatus(
    today: today,
    month: today.substring(0, 7),
    checkedToday: days.contains(today),
    streak: streak,
    daysToStreakBonus: 7 - streak % 7,
    totalDays: days.length,
    days: Set.of(days),
    justChecked: justChecked,
    earned: earned,
  );

  @override
  Future<AttendanceStatus> attendance({String? month}) async {
    if (fail) throw const ApiException('NETWORK', '연결이 불안정해요.');
    return _status();
  }

  @override
  Future<AttendanceStatus> checkIn() async {
    if (days.contains(today)) return _status();
    days.add(today);
    streak++;
    var earned = 3;
    await _give(3, 'ATTENDANCE', '출석 체크');
    if (streak % 7 == 0) {
      earned += 5;
      await _give(5, 'ATTENDANCE_STREAK', '7일 연속 출석 보너스');
    }
    return _status(justChecked: true, earned: earned);
  }

  @override
  Future<AdStatus> adStatus() async =>
      AdStatus(rewardPoints: 2, dailyMax: 5, todayCount: adToday, remaining: 5 - adToday);

  @override
  Future<AdStatus> devAdReward() async {
    if (adToday < 5) {
      adToday++;
      await _give(2, 'AD_REWARD', '광고 보상');
    }
    return adStatus();
  }

  @override
  Future<LedgerPage> history({String? cursor}) async => LedgerPage(List.of(ledger), null);

  @override
  Future<AchievementBook> achievements() async =>
      AchievementBook(List.of(book), (await _me()).titleId);

  @override
  Future<List<Achievement>> unseen() async => List.of(pending);

  @override
  Future<void> markSeen(List<String> ids) async {
    seen.addAll(ids);
    pending.removeWhere((a) => ids.contains(a.id));
  }

  @override
  Future<void> setTitle(String? achievementId) async {
    final u = await _me();
    u.titleId = achievementId;
    u.title = book.where((a) => a.id == achievementId).firstOrNull?.titleText;
  }

  Future<List<StationeryItem>> stationery() async => [
    StationeryItem('cream', '크림', '가입하면 바로 받아요', owned: owned.contains('cream')),
    StationeryItem('lined', '줄노트', '출석 7일을 채우면 열려요', owned: owned.contains('lined')),
    StationeryItem('sky-cloud', '하늘 구름', '10개 시를 방문하면 열려요', owned: owned.contains('sky-cloud')),
  ];
}

class FakeAdGateway implements AdGateway {
  FakeAdGateway({this.result = AdShowResult.rewarded});

  AdShowResult result;
  int shown = 0;

  @override
  Future<AdShowResult> showRewarded({required String userId, required bool underAge}) async {
    shown++;
    return result;
  }
}

List<Achievement> sampleAchievements() => [
  const Achievement(
    id: 'first-letter',
    name: '첫 편지',
    description: '처음으로 편지를 맡겼어요',
    rewardPoints: 2,
    titleText: '새내기 편지꾼',
    achieved: true,
    current: 1,
  ),
  const Achievement(
    id: 'attend-7',
    name: '출석 7일',
    description: '7일 출석했어요',
    rewardPoints: 3,
    stationeryId: 'lined',
    stationeryName: '줄노트',
    current: 3,
    target: 7,
  ),
  const Achievement(
    id: 'visit-city-10',
    name: '열 고을',
    description: '10개 시를 방문했어요',
    rewardPoints: 3,
    stationeryId: 'sky-cloud',
    stationeryName: '하늘 구름',
    current: 6,
    target: 10,
  ),
  const Achievement(
    id: 'pen-pal-5',
    name: '단짝',
    description: '같은 친구와 5번 주고받았어요',
    rewardPoints: 5,
    titleText: '단짝',
    target: 5,
  ),
];

/// 신고·차단·설정·공지 가짜 서버
class FakeSafetyApi extends SafetyApi {
  FakeSafetyApi(this.store, {this.backend})
    : super(ApiClient(baseUrl: 'http://fake.invalid', tokenStore: store));

  final MemoryTokenStore store;
  FakeBackend? backend;

  final reports = <(ReportTarget, String, String, String?)>[];
  final blocked = <String, String>{};
  final settings = <String, bool>{};
  final notices_ = <Notice>[];
  ApiException? reportError;

  /// 차단할 때 닉네임을 알 수 있게(실제 서버는 DB에서 찾는다)
  final names = <String, String>{'u-dubu': '두부염소', 'u-kong': '콩이네'};

  @override
  Future<void> report({
    required ReportTarget target,
    required String targetId,
    required String reason,
    String? detail,
  }) async {
    if (reportError != null) throw reportError!;
    reports.add((
      target,
      targetId,
      reason,
      detail == null || detail.trim().isEmpty ? null : detail.trim(),
    ));
  }

  @override
  Future<void> block(String userId) async => blocked[userId] = names[userId] ?? userId;

  @override
  Future<void> unblock(String userId) async => blocked.remove(userId);

  @override
  Future<List<BlockedUser>> blocks() async => [
    for (final e in blocked.entries) BlockedUser(e.key, e.value, fixtureNow),
  ];

  @override
  Future<void> updateSettings({bool? randomReceive, bool? notifyEnabled}) async {
    if (randomReceive != null) settings['randomReceive'] = randomReceive;
    if (notifyEnabled != null) settings['notifyEnabled'] = notifyEnabled;
    final t = store.tokens;
    if (backend != null && t != null) {
      final u = backend!._user(t.accessToken);
      if (randomReceive != null) u.randomReceive = randomReceive;
      if (notifyEnabled != null) u.notifyEnabled = notifyEnabled;
    }
  }

  @override
  Future<List<Notice>> notices() async => List.of(notices_);
}
