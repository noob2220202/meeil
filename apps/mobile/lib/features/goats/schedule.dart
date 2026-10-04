import 'package:flutter/painting.dart';

import '../map/goat_painter.dart';

enum GoatKind { delivery, rollingNation, rollingProvince, rollingCity }

GoatKind goatKindFrom(String raw) => switch (raw) {
  'DELIVERY' => GoatKind.delivery,
  'ROLLING_NATION' => GoatKind.rollingNation,
  'ROLLING_PROVINCE' => GoatKind.rollingProvince,
  _ => GoatKind.rollingCity,
};

class GoatInfo {
  const GoatInfo({
    required this.id,
    required this.kind,
    required this.name,
    required this.speedKmh,
    required this.look,
    this.scopeCode,
  });

  final String id;
  final GoatKind kind;
  final String name;
  final double speedKmh;
  final GoatLook look;
  final String? scopeCode;

  factory GoatInfo.fromJson(Map<String, dynamic> j) {
    final kind = goatKindFrom(j['kind'] as String);
    return GoatInfo(
      id: j['id'] as String,
      kind: kind,
      name: j['name'] as String,
      speedKmh: (j['speedKmh'] as num).toDouble(),
      scopeCode: j['scopeCode'] as String?,
      look: GoatLook(
        hat: colorFromHex(j['hatColor'] as String),
        bag: colorFromHex(j['bagColor'] as String),
        scroll: kind != GoatKind.delivery,
      ),
    );
  }
}

class GoatStop {
  const GoatStop({
    required this.regionCode,
    required this.arriveAt,
    required this.departAt,
    this.bySea = false,
    this.express = false,
  });

  final String regionCode;
  final DateTime arriveAt;
  final DateTime departAt;

  /// 이 정류까지 배·비행기로 왔는지
  final bool bySea;
  final bool express;

  factory GoatStop.fromJson(Map<String, dynamic> j) => GoatStop(
    regionCode: j['regionCode'] as String,
    arriveAt: DateTime.parse(j['arriveAt'] as String),
    departAt: DateTime.parse(j['departAt'] as String),
    bySea: j['travelMode'] == 'SEA',
    express: j['express'] as bool? ?? false,
  );
}

/// 어느 순간 염소의 상태
sealed class GoatMoment {
  const GoatMoment();
}

/// 지역에 머무는 중
class GoatStaying extends GoatMoment {
  const GoatStaying(this.stop, this.next);
  final GoatStop stop;
  final GoatStop? next;
}

/// 두 지역 사이를 이동 중. [progress] 0~1
class GoatTraveling extends GoatMoment {
  const GoatTraveling(this.from, this.to, this.progress);
  final GoatStop from;
  final GoatStop to;
  final double progress;
}

/// 받아 둔 스케줄 범위 밖
class GoatUnknown extends GoatMoment {
  const GoatUnknown();
}

/// 한 염소의 정류 목록(도착 시각 오름차순)
class GoatTrack {
  GoatTrack(this.goat, List<GoatStop> stops)
    : stops = [...stops]..sort((a, b) => a.arriveAt.compareTo(b.arriveAt));

  final GoatInfo goat;
  final List<GoatStop> stops;

  /// [t] 시각의 상태. 이진 탐색으로 마지막으로 도착한 정류를 찾는다.
  GoatMoment at(DateTime t) {
    if (stops.isEmpty || t.isBefore(stops.first.arriveAt)) return const GoatUnknown();
    var lo = 0, hi = stops.length - 1;
    while (lo < hi) {
      final mid = (lo + hi + 1) >> 1;
      if (stops[mid].arriveAt.isAfter(t)) {
        hi = mid - 1;
      } else {
        lo = mid;
      }
    }
    final cur = stops[lo];
    final next = lo + 1 < stops.length ? stops[lo + 1] : null;
    if (t.isBefore(cur.departAt)) return GoatStaying(cur, next);
    if (next == null) return const GoatUnknown();
    final total = next.arriveAt.difference(cur.departAt).inMilliseconds;
    final done = t.difference(cur.departAt).inMilliseconds;
    return GoatTraveling(cur, next, total <= 0 ? 1 : (done / total).clamp(0.0, 1.0));
  }

  /// [t] 이후 처음으로 [regionCode]에 도착하는 정류(머무는 중이면 그 정류)
  GoatStop? nextVisit(String regionCode, DateTime t) {
    for (final s in stops) {
      if (s.regionCode == regionCode && s.departAt.isAfter(t)) return s;
    }
    return null;
  }

  /// [t] 이후의 정류들(지금 머무는 곳 다음부터)
  List<GoatStop> upcoming(DateTime t, {int count = 3}) =>
      stops.where((s) => s.arriveAt.isAfter(t)).take(count).toList();
}

/// 서버에서 받은 스케줄 묶음
class GoatSchedule {
  GoatSchedule({
    required this.tracks,
    required this.clockOffset,
    required this.validUntil,
    required this.cityGoatLook,
  });

  final Map<String, GoatTrack> tracks;

  /// 서버 시각 - 기기 시각
  final Duration clockOffset;

  /// 이 시각이 가까워지면 다시 받는다
  final DateTime validUntil;
  final GoatLook cityGoatLook;

  DateTime serverNow([DateTime? deviceNow]) => (deviceNow ?? DateTime.now()).add(clockOffset);

  /// [requestStarted]~[responseReceived] 사이 왕복 시간의 가운데를 서버 시각과 맞춘다
  factory GoatSchedule.fromJson(
    Map<String, dynamic> j, {
    required DateTime requestStarted,
    required DateTime responseReceived,
  }) {
    final serverTime = DateTime.parse(j['serverTime'] as String);
    final mid = requestStarted.add(responseReceived.difference(requestStarted) ~/ 2);
    final goats = {
      for (final g in j['goats'] as List)
        (g as Map<String, dynamic>)['id'] as String: GoatInfo.fromJson(g),
    };
    final byGoat = <String, List<GoatStop>>{};
    for (final s in j['stops'] as List) {
      final m = s as Map<String, dynamic>;
      byGoat.putIfAbsent(m['goatId'] as String, () => []).add(GoatStop.fromJson(m));
    }
    final city = j['cityGoat'] as Map<String, dynamic>?;
    return GoatSchedule(
      tracks: {for (final e in goats.entries) e.key: GoatTrack(e.value, byGoat[e.key] ?? const [])},
      clockOffset: serverTime.difference(mid),
      validUntil: DateTime.parse(j['to'] as String),
      cityGoatLook: city == null
          ? RollingLooks.city
          : GoatLook(
              hat: colorFromHex(city['hatColor'] as String),
              bag: colorFromHex(city['bagColor'] as String),
              scroll: true,
            ),
    );
  }

  /// 지금 [regionCode]에 머무는 배달 염소들
  List<GoatInfo> deliveryGoatsIn(String regionCode, DateTime t) => [
    for (final tr in tracks.values)
      if (tr.goat.kind == GoatKind.delivery)
        if (tr.at(t) case GoatStaying(:final stop) when stop.regionCode == regionCode) tr.goat,
  ];

  /// [regionCode]에 다음으로 올 배달 염소와 도착 시각
  (GoatInfo, DateTime)? nextDeliveryTo(String regionCode, DateTime t) {
    (GoatInfo, DateTime)? best;
    for (final tr in tracks.values) {
      if (tr.goat.kind != GoatKind.delivery) continue;
      final s = tr.nextVisit(regionCode, t);
      if (s == null) continue;
      if (best == null || s.arriveAt.isBefore(best.$2)) best = (tr.goat, s.arriveAt);
    }
    return best;
  }
}

/// 남은 시간 "약 3시간 20분" 형태
String formatRemaining(Duration d) {
  if (d.inMinutes < 1) return '곧';
  final h = d.inHours;
  final m = d.inMinutes % 60;
  if (h == 0) return '$m분';
  if (m == 0) return '$h시간';
  return '$h시간 $m분';
}

/// 한국 시각(KST)으로 "오후 3:05" 형태. 기기 시간대와 무관하게 KST로 보여 준다(SPEC 11.2).
String formatClock(DateTime t) {
  final local = t.toUtc().add(const Duration(hours: 9));
  final h = local.hour;
  final ampm = h < 12 ? '오전' : '오후';
  final h12 = h % 12 == 0 ? 12 : h % 12;
  return '$ampm $h12:${local.minute.toString().padLeft(2, '0')}';
}

/// 경로 위 위치 보간(이동 중엔 살짝 위로 볼록한 곡선 대신 직선 + 부드러운 가감속)
Offset lerpTravel(Offset a, Offset b, double progress) {
  final t = progress < 0.5 ? 2 * progress * progress : 1 - 2 * (1 - progress) * (1 - progress);
  return Offset.lerp(a, b, 0.15 * progress + 0.85 * t)!;
}
