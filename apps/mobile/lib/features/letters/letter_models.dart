import '../map/goat_painter.dart';

/// 서버 편지 응답(보는 사람 관점)
enum LetterMode { direct, random, reply }

enum LetterStatus { handed, inTransit, delivered, read, eaten }

enum RandomScope { nation, province, city }

LetterMode _mode(String s) => switch (s) {
  'RANDOM' => LetterMode.random,
  'REPLY' => LetterMode.reply,
  _ => LetterMode.direct,
};

LetterStatus _status(String s) => switch (s) {
  'IN_TRANSIT' => LetterStatus.inTransit,
  'DELIVERED' => LetterStatus.delivered,
  'READ' => LetterStatus.read,
  'EATEN' => LetterStatus.eaten,
  _ => LetterStatus.handed,
};

String randomScopeApi(RandomScope s) => switch (s) {
  RandomScope.nation => 'NATION',
  RandomScope.province => 'PROVINCE',
  RandomScope.city => 'CITY',
};

/// 편지지에 붙인 스티커(위치는 편지지 기준 0~1)
class PlacedSticker {
  const PlacedSticker(this.id, this.x, this.y);

  final String id;
  final double x;
  final double y;

  factory PlacedSticker.fromJson(Map<String, dynamic> j) =>
      PlacedSticker(j['id'] as String, (j['x'] as num).toDouble(), (j['y'] as num).toDouble());

  Map<String, dynamic> toJson() => {'id': id, 'x': x, 'y': y};

  PlacedSticker moved(double nx, double ny) =>
      PlacedSticker(id, nx.clamp(0.0, 1.0), ny.clamp(0.0, 1.0));
}

class LetterPhoto {
  const LetterPhoto({
    required this.url,
    required this.width,
    required this.height,
    required this.blurred,
  });

  final String url;
  final int width;
  final int height;

  /// 랜덤 편지 사진: 받는 쪽은 탭해야 보인다(SPEC 5.2)
  final bool blurred;
}

class Person {
  const Person({required this.id, required this.nickname, this.title});

  final String id;
  final String nickname;
  final String? title;

  factory Person.fromJson(Map<String, dynamic> j) => Person(
    id: j['id'] as String,
    nickname: j['nickname'] as String? ?? '',
    title: j['title'] as String?,
  );

  Map<String, dynamic> toJson() => {'id': id, 'nickname': nickname, 'title': title};
}

class Letter {
  const Letter({
    required this.id,
    required this.mode,
    required this.isSender,
    required this.status,
    required this.sender,
    required this.recipient,
    required this.body,
    required this.stationeryId,
    required this.stickers,
    required this.photo,
    required this.handedAt,
    this.etaAt,
    this.deliveredAt,
    this.readAt,
    this.goatId,
    this.goatName,
    this.goatLook,
    this.express = false,
    this.replyToId,
    this.trashedAt,
    this.canReply = false,
    this.originRegionCode,
    this.destRegionCode,
    this.randomScope,
  });

  final String id;
  final LetterMode mode;
  final bool isSender;
  final LetterStatus status;
  final Person sender;

  /// 랜덤 편지는 도착 전까지 보낸 사람에게 받는 사람을 감춘다
  final Person? recipient;

  /// 염소가 먹어버린 편지는 null
  final String? body;
  final String stationeryId;
  final List<PlacedSticker> stickers;
  final LetterPhoto? photo;
  final DateTime handedAt;
  final DateTime? etaAt;
  final DateTime? deliveredAt;
  final DateTime? readAt;
  final String? goatId;
  final String? goatName;

  /// 배달한 염소의 모자·가방 색(도착 연출용)
  final GoatLook? goatLook;
  final bool express;
  final String? replyToId;
  final DateTime? trashedAt;
  final bool canReply;
  final String? originRegionCode;
  final String? destRegionCode;
  final String? randomScope;

  bool get isUnread => !isSender && status == LetterStatus.delivered;
  bool get isEaten => status == LetterStatus.eaten;
  bool get inTrash => trashedAt != null;

  static DateTime? _date(Object? v) => v == null ? null : DateTime.parse(v as String);

  factory Letter.fromJson(Map<String, dynamic> j) {
    final goat = j['goat'] as Map<String, dynamic>?;
    final photo = j['photo'] as Map<String, dynamic>?;
    final recipient = j['recipient'] as Map<String, dynamic>?;
    return Letter(
      id: j['id'] as String,
      mode: _mode(j['mode'] as String),
      isSender: j['role'] == 'sender',
      status: _status(j['status'] as String),
      sender: Person.fromJson(j['sender'] as Map<String, dynamic>),
      recipient: recipient == null ? null : Person.fromJson(recipient),
      body: j['body'] as String?,
      stationeryId: j['stationeryId'] as String,
      stickers: [
        for (final s in j['stickers'] as List? ?? const [])
          PlacedSticker.fromJson(s as Map<String, dynamic>),
      ],
      photo: photo == null
          ? null
          : LetterPhoto(
              url: photo['url'] as String,
              width: photo['width'] as int,
              height: photo['height'] as int,
              blurred: photo['blurred'] as bool? ?? false,
            ),
      handedAt: DateTime.parse(j['handedAt'] as String),
      etaAt: _date(j['etaAt']),
      deliveredAt: _date(j['deliveredAt']),
      readAt: _date(j['readAt']),
      goatId: goat?['id'] as String?,
      goatName: goat?['name'] as String?,
      goatLook: goat?['hatColor'] is String && goat?['bagColor'] is String
          ? GoatLook(
              hat: colorFromHex(goat!['hatColor'] as String),
              bag: colorFromHex(goat['bagColor'] as String),
            )
          : null,
      express: j['express'] as bool? ?? false,
      replyToId: j['replyToId'] as String?,
      trashedAt: _date(j['trashedAt']),
      canReply: j['canReply'] as bool? ?? false,
      originRegionCode: j['originRegionCode'] as String?,
      destRegionCode: j['destRegionCode'] as String?,
      randomScope: j['randomScope'] as String?,
    );
  }
}

class LetterPage {
  const LetterPage(this.letters, this.nextCursor);
  final List<Letter> letters;
  final String? nextCursor;
}

/// 스티커 20종 (서버 STICKER_IDS와 같아야 한다)
const stickerIds = [
  'heart',
  'star',
  'flower',
  'clover',
  'cloud',
  'sun',
  'moon',
  'note',
  'letter',
  'gift',
  'ribbon',
  'rainbow',
  'cherry',
  'leaf',
  'goat-smile',
  'goat-love',
  'goat-sleep',
  'goat-wow',
  'goat-laugh',
  'goat-tear',
];

const letterBodyMax = 200;
const stickersMax = 3;
