import 'dart:async';
import 'package:audioplayers/audioplayers.dart';

class SoundService {
  static const int _poolSize = 5;
  static final List<AudioPlayer> _pool = [];
  static int _poolIndex = 0;
  static bool _initialized = false;

  static Future<void> init() async {
    if (_initialized && _pool.isNotEmpty) return;
    _pool.clear();
    for (int i = 0; i < _poolSize; i++) {
      _pool.add(AudioPlayer());
    }
    _initialized = true;
  }

  static void playClick() {
    unawaited(_play('sounds/click.wav', 0.6));
  }

  static void playSuccess() {
    unawaited(_play('sounds/success.wav', 0.8));
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
