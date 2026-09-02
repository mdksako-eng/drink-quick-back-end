// services/tts/tts_factory.dart
// Platform-correct TTS: browser SpeechSynthesis on web, flutter_tts natively.
// Conditional export happens at compile time — no runtime branching needed.

export 'tts_stub.dart'
    if (dart.library.html) 'tts_web.dart'
    if (dart.library.io) 'tts_io.dart';
