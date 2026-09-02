// services/tts/tts_stub.dart
// Default (unimplemented) TTS bindings — overridden per-platform by
// tts_factory.dart's conditional export.

Future<void> platformInitTts() async {}

Future<void> platformSpeak(String text) async {}

Future<void> platformStopTts() async {}
