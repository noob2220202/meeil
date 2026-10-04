import 'dart:async';
import 'dart:convert';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import 'api_client.dart';
import 'config.dart';

/// 알림 데이터 → 열 화면 경로
String? routeForPush(Map<String, dynamic> data) => switch (data['type']) {
  'letter' || 'letter-eaten' when data['letterId'] is String => '/letters/${data['letterId']}',
  'rolling-eaten' when data['paperId'] is String => '/rolling/${data['paperId']}',
  'notice' => '/notices',
  'goat' => '/',
  _ => null,
};

/// 푸시(FCM) 연결. 설정이 없으면 아무것도 하지 않는다.
class PushService {
  PushService({required this.client, required this.onOpen, required this.onMessage});

  final ApiClient client;

  /// 알림을 눌러 열 경로
  final void Function(String route) onOpen;

  /// 앱이 켜져 있을 때 온 알림(편지함 새로고침 등)
  final VoidCallback onMessage;

  static const _channel = AndroidNotificationChannel(
    'letters',
    '편지와 염소',
    description: '편지 도착, 우리 동네에 온 염소 알림',
    importance: Importance.high,
  );

  final _local = FlutterLocalNotificationsPlugin();
  final _subs = <StreamSubscription<dynamic>>[];
  bool _started = false;
  String? _token;

  Future<void> start() async {
    if (_started || !AppConfig.pushEnabled) return;
    _started = true;
    try {
      await Firebase.initializeApp(
        options: const FirebaseOptions(
          apiKey: AppConfig.firebaseApiKey,
          appId: AppConfig.firebaseAppId,
          messagingSenderId: AppConfig.firebaseSenderId,
          projectId: AppConfig.firebaseProjectId,
        ),
      );
      await _local.initialize(
        settings: const InitializationSettings(
          android: AndroidInitializationSettings('@mipmap/ic_launcher'),
        ),
        onDidReceiveNotificationResponse: (r) {
          final payload = r.payload;
          if (payload == null) return;
          final route = routeForPush(jsonDecode(payload) as Map<String, dynamic>);
          if (route != null) onOpen(route);
        },
      );
      await _local
          .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()
          ?.createNotificationChannel(_channel);

      final messaging = FirebaseMessaging.instance;
      _token = await messaging.getToken();
      if (_token != null) await _register(_token!);
      _subs.add(
        messaging.onTokenRefresh.listen((t) {
          _token = t;
          _register(t);
        }),
      );
      _subs.add(FirebaseMessaging.onMessage.listen(_showForeground));
      _subs.add(FirebaseMessaging.onMessageOpenedApp.listen(_open));
      final initial = await messaging.getInitialMessage();
      if (initial != null) _open(initial);
    } catch (e) {
      // 푸시가 안 되어도 앱은 쓸 수 있다(편지함은 1분마다 확인)
      debugPrint('푸시 설정 실패: $e');
    }
  }

  Future<void> _register(String token) async {
    try {
      await client.put('/me/fcm-token', {'token': token});
    } on ApiException {
      // 다음 실행 때 다시 등록한다
    }
  }

  void _open(RemoteMessage m) {
    final route = routeForPush(m.data);
    if (route != null) onOpen(route);
  }

  Future<void> _showForeground(RemoteMessage m) async {
    onMessage();
    final n = m.notification;
    if (n == null) return;
    await _local.show(
      id: m.hashCode,
      title: n.title,
      body: n.body,
      notificationDetails: NotificationDetails(
        android: AndroidNotificationDetails(
          _channel.id,
          _channel.name,
          channelDescription: _channel.description,
          importance: Importance.high,
          priority: Priority.high,
        ),
      ),
      payload: jsonEncode(m.data),
    );
  }

  /// 로그아웃: 이 기기 토큰을 서버에서 지운다
  Future<void> stop() async {
    for (final s in _subs) {
      await s.cancel();
    }
    _subs.clear();
    final t = _token;
    if (t != null) {
      try {
        await client.dio.delete<void>('/me/fcm-token', data: {'token': t});
      } catch (_) {}
    }
    _started = false;
  }
}
