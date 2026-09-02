// services/tts/tts_io.dart
// Native (Android/iOS/Windows/macOS/Linux) TTS via flutter_tts.

import 'package:flutter_tts/flutter_tts.dart';

final FlutterTts _tts = FlutterTts();
bool _initialized = false;

Future<void> platformInitTts() async {
  if (_initialized) return;
  await _tts.setLanguage('en-US');
  await _tts.setSpeechRate(0.5);
  _initialized = true;
}

Future<void> platformSpeak(String text) async {
  await platformInitTts();
  await _tts.stop();
  await _tts.speak(text);
}

Future<void> platformStopTts() async {
  await _tts.stop();
}
