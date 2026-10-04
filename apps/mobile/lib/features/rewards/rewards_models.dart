/// 출석 현황 (GET/POST /attendance)
class AttendanceStatus {
  const AttendanceStatus({
    required this.today,
    required this.month,
    required this.checkedToday,
    required this.streak,
    required this.daysToStreakBonus,
    required this.totalDays,
    required this.days,
    this.dailyPoints = 3,
    this.streakBonus = 5,
    this.streakDays = 7,
    this.justChecked = false,
    this.earned = 0,
  });

  /// KST 'YYYY-MM-DD'
  final String today;
  final String month;
  final bool checkedToday;
  final int streak;
  final int daysToStreakBonus;
  final int totalDays;
  final Set<String> days;
  final int dailyPoints;
  final int streakBonus;
  final int streakDays;

  /// 방금 출석해서 받은 포인트(POST 응답에서만)
  final bool justChecked;
  final int earned;

  factory AttendanceStatus.fromJson(Map<String, dynamic> j) {
    final p = j['points'] as Map<String, dynamic>? ?? const {};
    return AttendanceStatus(
      today: j['today'] as String,
      month: j['month'] as String,
      checkedToday: j['checkedToday'] as bool,
      streak: j['streak'] as int,
      daysToStreakBonus: j['daysToStreakBonus'] as int,
      totalDays: j['totalDays'] as int,
      days: {for (final d in j['days'] as List) d as String},
      dailyPoints: p['daily'] as int? ?? 3,
      streakBonus: p['streakBonus'] as int? ?? 5,
      streakDays: p['streakDays'] as int? ?? 7,
      justChecked: j['checkedIn'] as bool? ?? false,
      earned: [
        for (final r in (j['rewards'] as List? ?? const []))
          (r as Map<String, dynamic>)['points'] as int,
      ].fold(0, (a, b) => a + b),
    );
  }
}

class AdStatus {
  const AdStatus({
    required this.rewardPoints,
    required this.dailyMax,
    required this.todayCount,
    required this.remaining,
  });

  final int rewardPoints;
  final int dailyMax;
  final int todayCount;
  final int remaining;

  factory AdStatus.fromJson(Map<String, dynamic> j) => AdStatus(
    rewardPoints: j['rewardPoints'] as int,
    dailyMax: j['dailyMax'] as int,
    todayCount: j['todayCount'] as int,
    remaining: j['remaining'] as int,
  );
}

class LedgerEntry {
  const LedgerEntry({
    required this.id,
    required this.delta,
    required this.balanceAfter,
    required this.reason,
    required this.label,
    required this.createdAt,
  });

  final String id;
  final int delta;
  final int balanceAfter;
  final String reason;
  final String label;
  final DateTime createdAt;

  factory LedgerEntry.fromJson(Map<String, dynamic> j) => LedgerEntry(
    id: j['id'] as String,
    delta: j['delta'] as int,
    balanceAfter: j['balanceAfter'] as int,
    reason: j['reason'] as String,
    label: j['label'] as String,
    createdAt: DateTime.parse(j['createdAt'] as String),
  );
}

class LedgerPage {
  const LedgerPage(this.entries, this.nextCursor);
  final List<LedgerEntry> entries;
  final String? nextCursor;
}

class Achievement {
  const Achievement({
    required this.id,
    required this.name,
    required this.description,
    required this.rewardPoints,
    this.titleText,
    this.stationeryId,
    this.stationeryName,
    this.achieved = false,
    this.achievedAt,
    this.current = 0,
    this.target = 1,
  });

  final String id;
  final String name;
  final String description;
  final int rewardPoints;
  final String? titleText;
  final String? stationeryId;
  final String? stationeryName;
  final bool achieved;
  final DateTime? achievedAt;
  final int current;
  final int target;

  double get progress => target <= 0 ? 1 : (current / target).clamp(0, 1).toDouble();

  factory Achievement.fromJson(Map<String, dynamic> j) {
    final p = j['progress'] as Map<String, dynamic>?;
    final at = j['achievedAt'] as String?;
    return Achievement(
      id: j['id'] as String,
      name: j['name'] as String,
      description: j['description'] as String,
      rewardPoints: j['rewardPoints'] as int? ?? 0,
      titleText: j['titleText'] as String?,
      stationeryId: j['stationeryId'] as String?,
      stationeryName: j['stationeryName'] as String?,
      achieved: j['achieved'] as bool? ?? false,
      achievedAt: at == null ? null : DateTime.parse(at),
      current: p?['current'] as int? ?? 0,
      target: p?['target'] as int? ?? 1,
    );
  }
}

class AchievementBook {
  const AchievementBook(this.achievements, this.titleAchievementId);
  final List<Achievement> achievements;
  final String? titleAchievementId;

  int get achievedCount => achievements.where((a) => a.achieved).length;
}
