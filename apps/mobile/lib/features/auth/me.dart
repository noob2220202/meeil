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

  bool get onboardingCompleted => termsAgreed && birthDateSet && nicknameSet;
}
