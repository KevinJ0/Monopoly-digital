import 'dart:async';
import 'package:audioplayers/audioplayers.dart';

class SoundService {
  static const int _poolSize = 8;
  static final AudioContext effectsAudioContext = AudioContext(
    android: const AudioContextAndroid(
      contentType: AndroidContentType.sonification,
      usageType: AndroidUsageType.game,
      audioFocus: AndroidAudioFocus.none,
    ),
    iOS: AudioContextIOS(
      category: AVAudioSessionCategory.playback,
      options: const {AVAudioSessionOptions.mixWithOthers},
    ),
  );
  static final List<AudioPlayer> _pool = [];
  static int _poolIndex = 0;
  static bool _initialized = false;

  static Future<void> init() async {
    if (_initialized && _pool.isNotEmpty) return;
    await AudioPlayer.global.setAudioContext(effectsAudioContext);
    _pool.clear();
    for (int i = 0; i < _poolSize; i++) {
      final player = AudioPlayer();
      await player.setAudioContext(effectsAudioContext);
      _pool.add(player);
    }
    _poolIndex = 0;
    _initialized = true;
  }

  static void playClick() {
    unawaited(_play('sounds/click.wav', 0.6));
  }

  static void playSuccess() {
    unawaited(_play('sounds/success.wav', 0.8));
  }

  static void playDiceRoll() {
    unawaited(_play('sounds/dice_roll.wav', 0.8));
  }

  static void playMoneyCount() {
    unawaited(_play('sounds/money_count.wav', 0.7));
  }

  static void playFanfare() {
    unawaited(_play('sounds/fanfare.wav', 0.9));
  }

  static void playSadTrombone() {
    unawaited(_play('sounds/sad_trombone.wav', 0.8));
  }

  static void playCardFlip() {
    unawaited(_play('sounds/card_flip.wav', 0.7));
  }

  static void playPropertyBuy() {
    unawaited(_play('sounds/property_buy.wav', 0.8));
  }

  static void playPop() {
    unawaited(_play('sounds/pop.wav', 0.6));
  }

  static Future<void> _play(String asset, double volume) async {
    if (!_initialized || _pool.isEmpty) await init();
    try {
      final player = _pool[_poolIndex % _pool.length];
      _poolIndex++;
      await player.stop();
      await player.play(AssetSource(asset), volume: volume);
    } catch (_) {}
  }
}
