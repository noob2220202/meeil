/// 서버 `/me` 응답. 생년월일 등 비공개 정보는 서버가 보내지 않는다.
class Me {
  const Me({
    required this.id,
    required this.nickname,
    required this.status,
    required this.pointsBalance,
    required this.termsAgreed,
    required this.birthDateSet,
    required this.nicknameSet,
    this.nicknameChangeableAt,
    this.title,
    this.titleAchievementId,
    this.adsUnderAge = true,
    this.randomReceive = true,
    this.notifyEnabled = true,
  });

  factory Me.fromJson(Map<String, dynamic> j) {
    final ob = j['onboarding'] as Map<String, dynamic>;
    final changeable = j['nicknameChangeableAt'] as String?;
    return Me(
      id: j['id'] as String,
      nickname: j['nickname'] as String?,
      status: j['status'] as String,
      pointsBalance: j['pointsBalance'] as int,
      termsAgreed: ob['termsAgreed'] as bool,
      birthDateSet: ob['birthDateSet'] as bool,
      nicknameSet: ob['nicknameSet'] as bool,
      nicknameChangeableAt: changeable == null ? null : DateTime.parse(changeable),
      title: j['title'] as String?,
      titleAchievementId: j['titleAchievementId'] as String?,
      randomReceive: j['randomReceive'] as bool? ?? true,
      notifyEnabled: j['notifyEnabled'] as bool? ?? true,
      adsUnderAge: (j['ads'] as Map<String, dynamic>?)?['underAge'] as bool? ?? true,
    );
  }

  final String id;
  final String? nickname;
  final String status;
  final int pointsBalance;
  final bool termsAgreed;
  final bool birthDateSet;
  final bool nicknameSet;
  final DateTime? nicknameChangeableAt;

  /// 닉네임 옆 칭호
  final String? title;
  final String? titleAchievementId;

  /// 광고 요청에 청소년 설정을 적용할지(생년월일은 서버만 안다)
  final bool adsUnderAge;

  /// 랜덤 편지 받기 (SPEC 9.1)
  final bool randomReceive;

  /// 편지 도착·염소 알림
  final bool notifyEnabled;

  bool get onboardingCompleted => termsAgreed && birthDateSet && nicknameSet;
}
