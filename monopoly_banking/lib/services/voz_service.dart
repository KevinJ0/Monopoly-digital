import 'package:flutter_tts/flutter_tts.dart';

class VozService {
  static final VozService _instance = VozService._internal();
  factory VozService() => _instance;
  VozService._internal();

  final FlutterTts _tts = FlutterTts();
  bool _initialized = false;

  Future<void> init() async {
    if (_initialized) return;
    await _tts.setLanguage("es-MX");
    await _tts.setSpeechRate(0.7);
    await _tts.setVolume(1.0);
    await _tts.setPitch(1.0);
    _initialized = true;
  }

  Future<void> hablar(String texto) async {
    await init();
    await _tts.speak(texto);
  }
}
