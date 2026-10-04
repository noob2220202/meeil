import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api_client.dart';
import '../auth/session.dart';
import 'letter_models.dart';

enum MailBox { inbox, sent, trash }

class HandRequest {
  const HandRequest({
    required this.mode,
    required this.body,
    required this.stationeryId,
    required this.stickers,
    required this.clientRequestId,
    this.recipientId,
    this.replyToId,
    this.randomScope,
    this.photoId,
  });

  final LetterMode mode;
  final String body;
  final String stationeryId;
  final List<PlacedSticker> stickers;
  final String clientRequestId;
  final String? recipientId;
  final String? replyToId;
  final RandomScope? randomScope;
  final String? photoId;

  Map<String, dynamic> toJson() => {
    'mode': switch (mode) {
      LetterMode.direct => 'DIRECT',
      LetterMode.random => 'RANDOM',
      LetterMode.reply => 'REPLY',
    },
    'body': body,
    'stationeryId': stationeryId,
    'stickers': [for (final s in stickers) s.toJson()],
    'clientRequestId': clientRequestId,
    'recipientId': ?recipientId,
    'replyToId': ?replyToId,
    if (randomScope != null) 'randomScope': randomScopeApi(randomScope!),
    'photoId': ?photoId,
  };
}

class LettersApi {
  LettersApi(this.client);

  final ApiClient client;

  Future<Letter> hand(HandRequest req) async =>
      Letter.fromJson(await client.post('/letters', req.toJson()));

  Future<LetterPage> list(MailBox box, {String? cursor}) async {
    final j = await client.get('/letters/${box.name}', query: {'cursor': ?cursor});
    return LetterPage([
      for (final l in j['letters'] as List) Letter.fromJson(l as Map<String, dynamic>),
    ], j['nextCursor'] as String?);
  }

  Future<int> unreadCount() async => (await client.get('/letters/unread-count'))['count'] as int;

  Future<Letter> get(String id) async => Letter.fromJson(await client.get('/letters/$id'));
  Future<Letter> markRead(String id) async =>
      Letter.fromJson(await client.post('/letters/$id/read', const {}));
  Future<Letter> trash(String id) async =>
      Letter.fromJson(await client.post('/letters/$id/trash', const {}));
  Future<Letter> restore(String id) async =>
      Letter.fromJson(await client.post('/letters/$id/restore', const {}));
  Future<void> purge(String id) => client.delete('/letters/$id');

  Future<List<Person>> searchUsers(String nick) async {
    final j = await client.get('/users/search', query: {'nick': nick});
    return [for (final u in j['users'] as List) Person.fromJson(u as Map<String, dynamic>)];
  }

  /// 사진 올리기: 서버가 EXIF 제거·리사이즈·WebP 변환을 한다. photoId를 돌려준다.
  Future<String> uploadPhoto(String path) async {
    final form = FormData.fromMap({'photo': await MultipartFile.fromFile(path)});
    final j = await client.postForm('/photos', form);
    return j['photoId'] as String;
  }
}

final lettersApiProvider = Provider<LettersApi>((ref) => LettersApi(ref.watch(apiClientProvider)));
