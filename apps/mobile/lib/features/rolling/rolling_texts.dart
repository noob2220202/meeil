import '../../core/korean.dart';
import '../goats/schedule.dart';
import 'rolling_models.dart';

DateTime _kst(DateTime t) => t.toUtc().add(const Duration(hours: 9));

/// "10월 3일"
String kstDate(DateTime t) {
  final k = _kst(t);
  return '${k.month}월 ${k.day}일';
}

/// 장 기간: 시는 "10월 3일", 전국·도는 "9월 28일 ~ 10월 4일"
String periodLabel(RollingPaper p) {
  final last = p.periodEnd.subtract(const Duration(milliseconds: 1));
  final a = kstDate(p.periodStart);
  final b = kstDate(last);
  return a == b ? a : '$a ~ $b';
}

/// 마감까지 남은 시간: "마감까지 3일" / "마감까지 5시간 20분"
String closesIn(RollingPaper p, DateTime now) {
  final d = p.periodEnd.difference(now);
  if (d.isNegative) return '마감됐어요';
  if (d.inHours >= 24) return '마감까지 ${(d.inHours / 24).ceil()}일';
  return '마감까지 ${formatRemaining(d)}';
}

/// "오늘 오후 3:20" / "내일 오전 9:05" / "10월 6일 오후 1:00" (KST)
String dayClock(DateTime t, DateTime now) {
  final a = _kst(t);
  final b = _kst(now);
  final days = DateTime.utc(
    a.year,
    a.month,
    a.day,
  ).difference(DateTime.utc(b.year, b.month, b.day)).inDays;
  final day = switch (days) {
    0 => '오늘',
    1 => '내일',
    2 => '모레',
    _ => '${a.month}월 ${a.day}일',
  };
  return '$day ${formatClock(t)}';
}

/// 카드·바닥에 쓰는 내 참여 상태 한 줄
String joinStatusLine(RollingView v, DateTime now) {
  if (v.closed) return '마감된 두루마리예요';
  if (v.joined) return '한마디 남겼어요';
  if (v.canJoin) return '지금 한마디 남길 수 있어요!';
  final goat = v.paper.level.goatTitle;
  return switch (v.joinBlock) {
    JoinBlock.noGoatHere when v.goatNextArriveAt != null =>
      '${iGa(goat)} ${dayClock(v.goatNextArriveAt!, now)}에 와요',
    JoinBlock.noGoatHere => '이번 장엔 ${iGa(goat)} 우리 동네에 안 들러요',
    JoinBlock.regionUnknown => '지금 있는 시를 확인하면 참여할 수 있어요',
    JoinBlock.notInScope => '그 지역에 있을 때만 참여할 수 있어요',
    _ => '지금은 참여할 수 없어요',
  };
}
