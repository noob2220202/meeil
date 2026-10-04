import 'dart:async';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app_flags.dart';

/// 효과음 (SPEC 12.3). 소리는 tools/sounds가 합성해 만든 WAV.
enum Sfx {
  bleat('goat-bleat-1'),
  bleatShort('goat-bleat-2'),
  letterOpen('letter-open'),
  stamp('stamp'),
  points('points'),
  chomp('chomp');

  const Sfx(this.file);
  final String file;
}

abstract interface class SoundPlayer {
  Future<void> play(Sfx sfx);
}

/// 소리마다 저지연 플레이어 하나. 다른 앱 음악을 끊지 않고(mix), 무음 모드면 울리지 않는다.
class AudioSoundPlayer implements SoundPlayer {
  final _players = <Sfx, AudioPlayer>{};
  bool _configured = false;

  Future<AudioPlayer> _player(Sfx sfx) async {
    if (!_configured) {
      _configured = true;
      await AudioPlayer.global.setAudioContext(
        AudioContextConfig(
          focus: AudioContextConfigFocus.mixWithOthers,
          respectSilence: true,
        ).build(),
      );
    }
    return _players[sfx] ??= AudioPlayer(playerId: 'sfx-${sfx.name}')
      ..setPlayerMode(PlayerMode.lowLatency)
      ..setReleaseMode(ReleaseMode.stop);
  }

  @override
  Future<void> play(Sfx sfx) async {
    try {
      final p = await _player(sfx);
      await p.stop();
      await p.play(AssetSource('sounds/${sfx.file}.wav'), volume: 0.8);
    } catch (_) {
      // 소리는 꾸밈이다: 실패해도 조용히(무음 폴백)
    }
  }
}

final soundPlayerProvider = Provider<SoundPlayer>((ref) => AudioSoundPlayer());

/// 효과음 켜기/끄기(기기 설정, 기본 켬)
class SoundEnabled extends Notifier<bool> {
  static const _key = 'sound.enabled';

  @override
  bool build() => ref.watch(sharedPrefsProvider).getBool(_key) ?? true;

  Future<void> set(bool on) async {
    state = on;
    await ref.read(sharedPrefsProvider).setBool(_key, on);
  }
}

final soundEnabledProvider = NotifierProvider<SoundEnabled, bool>(SoundEnabled.new);

/// 화면에서 부르는 한 줄: `playSfx(ref, Sfx.bleat)`
void playSfx(WidgetRef ref, Sfx sfx) {
  if (!ref.read(soundEnabledProvider)) return;
  unawaited(ref.read(soundPlayerProvider).play(sfx));
}

/// 위젯 트리 어디서나(ProviderScope가 없으면 조용히 넘어간다)
void playSfxIn(BuildContext context, Sfx sfx) {
  try {
    final c = ProviderScope.containerOf(context, listen: false);
    if (!c.read(soundEnabledProvider)) return;
    unawaited(c.read(soundPlayerProvider).play(sfx));
  } catch (_) {
    // 스크린샷 등 Provider 없이 그린 경우
  }
}
