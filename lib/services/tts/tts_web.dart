// services/tts/tts_web.dart
// Web TTS via the browser's built-in SpeechSynthesis API (dart:html).
// flutter_tts has no web implementation, so without this, voice
// announcements silently failed on the Edge/web build.

// ignore: deprecated_member_use
import 'dart:html' as html;

bool _supported = false;

Future<void> platformInitTts() async {
  _supported = html.window.speechSynthesis != null;
}

Future<void> platformSpeak(String text) async {
  if (!_supported) return;
  try {
    html.window.speechSynthesis?.cancel();
    final utterance = html.SpeechSynthesisUtterance(text);
    utterance.lang = 'en-US';
    utterance.rate = 0.95;
    html.window.speechSynthesis?.speak(utterance);
  } catch (_) {
    // Voice is best-effort on web
  }
}

Future<void> platformStopTts() async {
  if (!_supported) return;
  html.window.speechSynthesis?.cancel();
}
