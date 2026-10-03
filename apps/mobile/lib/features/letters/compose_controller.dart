import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api_client.dart';
import '../../core/app_flags.dart';
import 'letter_models.dart';
import 'letters_api.dart';

/// 쓰는 중인 편지(기기에만 임시 저장 — SPEC 3.2, 5.3 DRAFT)
class ComposeDraft {
  const ComposeDraft({
    this.mode = LetterMode.direct,
    this.recipient,
    this.replyToId,
    this.randomScope = RandomScope.nation,
    this.body = '',
    this.stationeryId = 'cream',
    this.stickers = const [],
    this.photoPath,
    this.uploadedPhotoId,
    required this.clientRequestId,
  });

  final LetterMode mode;
  final Person? recipient;
  final String? replyToId;
  final RandomScope randomScope;
  final String body;
  final String stationeryId;
  final List<PlacedSticker> stickers;

  /// 고른 사진(기기 경로)
  final String? photoPath;

  /// 이미 올린 사진(다시 시도할 때 또 올리지 않는다)
  final String? uploadedPhotoId;

  /// 같은 편지를 두 번 맡기지 않도록 서버에 보내는 키
  final String clientRequestId;

  bool get isEmpty => body.trim().isEmpty && stickers.isEmpty && photoPath == null;
  int get length => body.trim().runes.length;
  bool get hasRecipient => switch (mode) {
    LetterMode.direct => recipient != null,
    LetterMode.reply => replyToId != null && recipient != null,
    LetterMode.random => true,
  };
  bool get ready => hasRecipient && length > 0 && length <= letterBodyMax;

  ComposeDraft copyWith({
    LetterMode? mode,
    Person? recipient,
    bool clearRecipient = false,
    String? replyToId,
    RandomScope? randomScope,
    String? body,
    String? stationeryId,
    List<PlacedSticker>? stickers,
    String? photoPath,
    bool clearPhoto = false,
    String? uploadedPhotoId,
  }) => ComposeDraft(
    mode: mode ?? this.mode,
    recipient: clearRecipient ? null : (recipient ?? this.recipient),
    replyToId: mode != null && mode != LetterMode.reply ? null : (replyToId ?? this.replyToId),
    randomScope: randomScope ?? this.randomScope,
    body: body ?? this.body,
    stationeryId: stationeryId ?? this.stationeryId,
    stickers: stickers ?? this.stickers,
    photoPath: clearPhoto ? null : (photoPath ?? this.photoPath),
    uploadedPhotoId: clearPhoto || photoPath != null
        ? uploadedPhotoId
        : (uploadedPhotoId ?? this.uploadedPhotoId),
    clientRequestId: clientRequestId,
  );

  Map<String, dynamic> toJson() => {
    'mode': mode.name,
    'recipient': recipient?.toJson(),
    'replyToId': replyToId,
    'randomScope': randomScope.name,
    'body': body,
    'stationeryId': stationeryId,
    'stickers': [for (final s in stickers) s.toJson()],
    'photoPath': photoPath,
    'uploadedPhotoId': uploadedPhotoId,
    'clientRequestId': clientRequestId,
  };

  factory ComposeDraft.fromJson(Map<String, dynamic> j) => ComposeDraft(
    mode: LetterMode.values.byName(j['mode'] as String? ?? 'direct'),
    recipient: j['recipient'] == null
        ? null
        : Person.fromJson(j['recipient'] as Map<String, dynamic>),
    replyToId: j['replyToId'] as String?,
    randomScope: RandomScope.values.byName(j['randomScope'] as String? ?? 'nation'),
    body: j['body'] as String? ?? '',
    stationeryId: j['stationeryId'] as String? ?? 'cream',
    stickers: [
      for (final s in j['stickers'] as List? ?? const [])
        PlacedSticker.fromJson(s as Map<String, dynamic>),
    ],
    photoPath: j['photoPath'] as String?,
    uploadedPhotoId: j['uploadedPhotoId'] as String?,
    clientRequestId: j['clientRequestId'] as String? ?? newRequestId(),
  );
}

String newRequestId() {
  final r = Random.secure();
  return List.generate(16, (_) => r.nextInt(256).toRadixString(16).padLeft(2, '0')).join();
}

/// 편지 쓰기 상태. 바뀔 때마다 기기에 저장한다.
class ComposeController extends Notifier<ComposeDraft> {
  static const _key = 'compose.draft.v1';
  Timer? _save;

  @override
  ComposeDraft build() {
    ref.onDispose(() => _save?.cancel());
    final raw = ref.read(sharedPrefsProvider).getString(_key);
    if (raw != null) {
      try {
        return ComposeDraft.fromJson(jsonDecode(raw) as Map<String, dynamic>);
      } catch (_) {
        // 깨진 임시저장은 버린다
      }
    }
    return ComposeDraft(clientRequestId: newRequestId());
  }

  void _set(ComposeDraft d) {
    state = d;
    _save?.cancel();
    _save = Timer(const Duration(milliseconds: 300), persist);
  }

  /// 즉시 저장(화면을 떠날 때)
  Future<void> persist() async {
    _save?.cancel();
    await ref.read(sharedPrefsProvider).setString(_key, jsonEncode(state.toJson()));
  }

  /// 답장 쓰기 시작. 다른 편지를 쓰던 중이면 새로 시작한다.
  void startReply(String replyToId, Person to) {
    if (state.mode == LetterMode.reply && state.replyToId == replyToId) return;
    _set(
      ComposeDraft(
        mode: LetterMode.reply,
        replyToId: replyToId,
        recipient: to,
        clientRequestId: newRequestId(),
      ),
    );
  }

  void startTo(Person to) => _set(state.copyWith(mode: LetterMode.direct, recipient: to));

  void setMode(LetterMode mode) =>
      _set(state.copyWith(mode: mode, clearRecipient: mode != state.mode));
  void setRecipient(Person p) => _set(state.copyWith(recipient: p));
  void setScope(RandomScope s) => _set(state.copyWith(randomScope: s));
  void setBody(String body) => _set(state.copyWith(body: body));
  void setStationery(String id) => _set(state.copyWith(stationeryId: id));
  void setPhoto(String? path) =>
      _set(path == null ? state.copyWith(clearPhoto: true) : state.copyWith(photoPath: path));

  void addSticker(String id) {
    if (state.stickers.length >= stickersMax) return;
    // 새 스티커는 오른쪽 위부터 조금씩 비켜 붙인다
    final n = state.stickers.length;
    _set(
      state.copyWith(
        stickers: [...state.stickers, PlacedSticker(id, 0.92 - n * 0.16, 0.04 + n * 0.05)],
      ),
    );
  }

  void moveSticker(int i, double x, double y) {
    final list = [...state.stickers];
    list[i] = list[i].moved(x, y);
    _set(state.copyWith(stickers: list));
  }

  void removeSticker(int i) => _set(state.copyWith(stickers: [...state.stickers]..removeAt(i)));

  /// 맡기기: 사진 올리기 → 편지 맡기기. 성공하면 임시저장을 비운다.
  Future<Letter> hand() async {
    final api = ref.read(lettersApiProvider);
    var d = state;
    if (d.photoPath != null && d.uploadedPhotoId == null) {
      final id = await api.uploadPhoto(d.photoPath!);
      d = d.copyWith(uploadedPhotoId: id);
      _set(d);
    }
    final letter = await api.hand(
      HandRequest(
        mode: d.mode,
        body: d.body.trim(),
        stationeryId: d.stationeryId,
        stickers: d.stickers,
        clientRequestId: d.clientRequestId,
        recipientId: d.mode == LetterMode.direct ? d.recipient?.id : null,
        replyToId: d.mode == LetterMode.reply ? d.replyToId : null,
        randomScope: d.mode == LetterMode.random ? d.randomScope : null,
        photoId: d.uploadedPhotoId,
      ),
    );
    await clear();
    return letter;
  }

  Future<void> clear() async {
    _save?.cancel();
    state = ComposeDraft(clientRequestId: newRequestId());
    await ref.read(sharedPrefsProvider).remove(_key);
  }
}

final composeProvider = NotifierProvider<ComposeController, ComposeDraft>(ComposeController.new);

/// 편지지 목록(가진 것 표시)
class StationeryItem {
  const StationeryItem(this.id, this.name, this.unlockHint, {required this.owned});
  final String id;
  final String name;
  final String unlockHint;
  final bool owned;
}

final stationeryProvider = FutureProvider<List<StationeryItem>>((ref) async {
  final j = await ref.watch(lettersApiProvider).client.get('/stationery');
  return [
    for (final s in j['stationery'] as List)
      StationeryItem(
        s['id'] as String,
        s['name'] as String,
        s['unlockHint'] as String,
        owned: s['owned'] as bool,
      ),
  ];
});

/// 서버 오류를 쓰기 화면 안내로
String handErrorMessage(ApiException e) => switch (e.code) {
  'INSUFFICIENT_POINTS' => '포인트가 부족해요. 출석하고 포인트를 모아 보세요.',
  _ => e.message,
};
