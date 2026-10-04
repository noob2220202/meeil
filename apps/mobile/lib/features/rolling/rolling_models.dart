import 'package:flutter/material.dart';

import '../../app/theme.dart';
import '../letters/letter_models.dart';
import '../map/goat_painter.dart';

/// 롤링페이퍼 레벨 (SPEC 6): 전국 주 1장 / 도 3일 1장 / 시 하루 1장
enum RollingLevel {
  nation('NATION', '전국', Palette.yellow, RollingLooks.nation),
  province('PROVINCE', '도', Palette.mint, RollingLooks.province),
  city('CITY', '시', Palette.pink, RollingLooks.city);

  const RollingLevel(this.api, this.label, this.color, this.look);

  final String api;
  final String label;
  final Color color;
  final GoatLook look;

  static RollingLevel parse(String s) => values.firstWhere((l) => l.api == s);

  /// "주 1장" 등
  String get cadence => switch (this) {
    RollingLevel.nation => '한 주에 한 장',
    RollingLevel.province => '사흘에 한 장',
    RollingLevel.city => '하루에 한 장',
  };

  /// 이 레벨 롤링 염소 부르는 말(조사용)
  String get goatTitle => switch (this) {
    RollingLevel.nation => '전국 두루마리 염소',
    RollingLevel.province => '도 두루마리 염소',
    RollingLevel.city => '동네 두루마리 염소',
  };
}

/// 참여 못 하는 이유(서버 joinBlock)
enum JoinBlock { alreadyJoined, regionUnknown, notInScope, noGoatHere, closed, other }

JoinBlock? parseJoinBlock(String? s) => switch (s) {
  null => null,
  'ALREADY_JOINED' => JoinBlock.alreadyJoined,
  'REGION_UNKNOWN' => JoinBlock.regionUnknown,
  'NOT_IN_SCOPE' => JoinBlock.notInScope,
  'NO_GOAT_HERE' => JoinBlock.noGoatHere,
  'CLOSED' => JoinBlock.closed,
  _ => JoinBlock.other,
};

class RollingPaper {
  const RollingPaper({
    required this.id,
    required this.level,
    required this.scopeCode,
    required this.scopeName,
    required this.periodStart,
    required this.periodEnd,
    this.topic,
    this.goatName,
    this.goatLook,
    this.entryCount,
  });

  final String id;
  final RollingLevel level;
  final String scopeCode;

  /// "전국" / "서울" / "서울 종로구"
  final String scopeName;
  final String? topic;
  final DateTime periodStart;
  final DateTime periodEnd;
  final String? goatName;
  final GoatLook? goatLook;

  /// 앨범 목록에서만
  final int? entryCount;

  /// 두루마리 제목: "전국 두루마리", "서울 두루마리", "종로구 두루마리"
  String get title {
    final short = level == RollingLevel.city ? scopeName.split(' ').last : scopeName;
    return '$short 두루마리';
  }

  GoatLook get look => goatLook ?? level.look;

  factory RollingPaper.fromJson(Map<String, dynamic> j) {
    final level = RollingLevel.parse(j['level'] as String);
    final goat = j['goat'] as Map<String, dynamic>?;
    return RollingPaper(
      id: j['id'] as String,
      level: level,
      scopeCode: j['scopeCode'] as String,
      scopeName: j['scopeName'] as String? ?? '',
      topic: j['topic'] as String?,
      periodStart: DateTime.parse(j['periodStart'] as String),
      periodEnd: DateTime.parse(j['periodEnd'] as String),
      goatName: goat?['name'] as String?,
      goatLook: goat?['hatColor'] is String && goat?['bagColor'] is String
          ? GoatLook(
              hat: colorFromHex(goat!['hatColor'] as String),
              bag: colorFromHex(goat['bagColor'] as String),
              scroll: true,
            )
          : null,
      entryCount: j['entryCount'] as int?,
    );
  }
}

class RollingEntry {
  const RollingEntry({
    required this.id,
    required this.author,
    required this.body,
    required this.stickers,
    required this.mine,
    required this.createdAt,
    this.eaten = false,
  });

  final String id;
  final Person author;

  /// 염소가 먹은 글은 null
  final String? body;
  final List<PlacedSticker> stickers;
  final bool mine;
  final bool eaten;
  final DateTime createdAt;

  factory RollingEntry.fromJson(Map<String, dynamic> j) => RollingEntry(
    id: j['id'] as String,
    author: Person.fromJson(j['author'] as Map<String, dynamic>),
    body: j['body'] as String?,
    stickers: [
      for (final s in (j['stickers'] as List? ?? const []))
        PlacedSticker.fromJson(s as Map<String, dynamic>),
    ],
    mine: j['mine'] as bool? ?? false,
    eaten: j['status'] == 'EATEN',
    createdAt: DateTime.parse(j['createdAt'] as String),
  );
}

/// 이번 장 + 내 참여 상태
class RollingView {
  const RollingView({
    required this.paper,
    required this.entries,
    required this.entryCount,
    required this.joined,
    required this.canJoin,
    required this.joinBlock,
    required this.goatHere,
    required this.closed,
    this.goatNextArriveAt,
  });

  final RollingPaper paper;

  /// 요약(/rolling/current/all)에서는 비어 있다
  final List<RollingEntry> entries;
  final int entryCount;
  final bool joined;
  final bool canJoin;
  final JoinBlock? joinBlock;
  final bool goatHere;
  final DateTime? goatNextArriveAt;
  final bool closed;

  factory RollingView.fromJson(Map<String, dynamic> j) {
    final entries = [
      for (final e in (j['entries'] as List? ?? const []))
        RollingEntry.fromJson(e as Map<String, dynamic>),
    ];
    final next = j['goatNextArriveAt'] as String?;
    return RollingView(
      paper: RollingPaper.fromJson(j['paper'] as Map<String, dynamic>),
      entries: entries,
      entryCount: j['entryCount'] as int? ?? entries.length,
      joined: j['joined'] as bool? ?? false,
      canJoin: j['canJoin'] as bool? ?? false,
      joinBlock: parseJoinBlock(j['joinBlock'] as String?),
      goatHere: j['goatHere'] as bool? ?? false,
      goatNextArriveAt: next == null ? null : DateTime.parse(next),
      closed: j['closed'] as bool? ?? false,
    );
  }

  RollingView withEntry(RollingEntry e) => RollingView(
    paper: paper,
    entries: [...entries, e],
    entryCount: entryCount + 1,
    joined: true,
    canJoin: false,
    joinBlock: JoinBlock.alreadyJoined,
    goatHere: goatHere,
    goatNextArriveAt: goatNextArriveAt,
    closed: closed,
  );
}

/// 롤링 탭 요약: 레벨별 이번 장 또는 오류 코드(위치 모름 등)
class RollingSummary {
  const RollingSummary(this.views, this.errors);

  final Map<RollingLevel, RollingView> views;
  final Map<RollingLevel, String> errors;

  factory RollingSummary.fromJson(Map<String, dynamic> j) {
    final views = <RollingLevel, RollingView>{};
    final errors = <RollingLevel, String>{};
    for (final level in RollingLevel.values) {
      final v = j[level.api] as Map<String, dynamic>?;
      if (v == null) continue;
      if (v['error'] != null) {
        errors[level] = v['error'] as String;
      } else {
        views[level] = RollingView.fromJson(v);
      }
    }
    return RollingSummary(views, errors);
  }
}
