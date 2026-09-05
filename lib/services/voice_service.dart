// services/voice_service.dart
import 'package:flutter/foundation.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;
import 'package:flutter_tts/flutter_tts.dart';
import 'package:shared_preferences/shared_preferences.dart';

class VoiceService {
  final stt.SpeechToText _speech = stt.SpeechToText();
  final FlutterTts _tts = FlutterTts();
  bool _isListening = false;
  bool _isInitialized = false;
  bool _ttsInitialized = false;

  /// 🌐 Global voice (TTS) switch for the WHOLE app — AI replies, order
  /// announcements, notifications, everything. Persisted per device.
  static bool voiceEnabled = true;
  static const String _voiceEnabledKey = 'app_voice_enabled';

  static Future<void> loadVoiceEnabled() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      voiceEnabled = prefs.getBool(_voiceEnabledKey) ?? true;
    } catch (_) {}
  }

  static Future<void> setVoiceEnabled(bool enabled) async {
    voiceEnabled = enabled;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_voiceEnabledKey, enabled);
    } catch (_) {}
  }

  bool get isListening => _isListening;
  bool get isInitialized => _isInitialized;

  Future<bool> initialize() async {
    // Initialize speech recognition (optional, may fail on some devices)
    try {
      _isInitialized = await _speech.initialize(
        onStatus: (status) => debugPrint('Speech status: $status'),
        onError: (error) => debugPrint('Speech error: $error'),
      );
      if (!_isInitialized) {
        debugPrint('Speech recognition not available - continuing with TTS only');
      }
    } catch (e) {
      debugPrint('Speech initialization failed: $e');
      _isInitialized = false;
    }

    // Initialize TTS (always works)
    try {
      await _tts.setLanguage('en-US');
      await _tts.setSpeechRate(0.5);
      await _tts.setVolume(1.0);
      await _tts.setPitch(1.0);
      _ttsInitialized = true;
      
      // Set callbacks for TTS
      _tts.setStartHandler(() {
        debugPrint('TTS started speaking');
      });
      _tts.setCompletionHandler(() {
        debugPrint('TTS completed');
      });
      _tts.setErrorHandler((msg) {
        debugPrint('TTS error: $msg');
      });
    } catch (e) {
      debugPrint('TTS initialization failed: $e');
      _ttsInitialized = false;
    }

    return _isInitialized || _ttsInitialized;
  }

  Future<void> startListening({
    required Function(String) onResult,
    required Function(String) onError,
  }) async {
    // If speech recognition is not available, show error
    if (!_isInitialized) {
      onError('Speech recognition is not available on this device. Please type your message instead.');
      return;
    }

    // Cancel any existing listening session
    if (_isListening) {
      await stopListening();
    }

    _isListening = true;
    
    try {
      await _speech.listen(
        onResult: (result) {
          if (result.finalResult) {
            onResult(result.recognizedWords);
            _isListening = false;
          }
        },
        listenFor: const Duration(seconds: 10),
        pauseFor: const Duration(seconds: 3),
        partialResults: false,
        cancelOnError: true,
        listenMode: stt.ListenMode.dictation,
        localeId: 'en_US',
      );
    } catch (e) {
      onError('Failed to start listening: $e');
      _isListening = false;
    }
  }

  Future<void> stopListening() async {
    _isListening = false;
    if (_isInitialized) {
      await _speech.stop();
    }
  }

  Future<void> cancelListening() async {
    _isListening = false;
    if (_isInitialized) {
      await _speech.cancel();
    }
  }

  Future<void> speak(String text) async {
    if (text.isEmpty) return;
    if (!voiceEnabled) return; // 🌐 Global app-wide voice switch
    if (!_ttsInitialized) {
      debugPrint('TTS not initialized, cannot speak: $text');
      return;
    }
    
    try {
      await _tts.speak(text);
    } catch (e) {
      debugPrint('TTS Error: $e');
    }
  }

  Future<void> stopSpeaking() async {
    if (_ttsInitialized) {
      await _tts.stop();
    }
  }

  Future<void> updateSpeechSettings({double? rate, String? language}) async {
    if (!_ttsInitialized) return;
    
    if (rate != null) {
      await _tts.setSpeechRate(rate);
    }
    if (language != null) {
      await _tts.setLanguage(language);
    }
  }

  Future<void> setVoiceGender(String gender) async {
    if (!_ttsInitialized) return;
    
    if (gender == 'male') {
      await _tts.setPitch(0.8);
    } else {
      await _tts.setPitch(1.2);
    }
  }
  
  Future<void> setSpeechRate(double rate) async {
    if (!_ttsInitialized) return;
    await _tts.setSpeechRate(rate);
  }
  
  Future<void> setLanguage(String languageCode) async {
    if (!_ttsInitialized) return;
    await _tts.setLanguage(languageCode);
  }
  
  Future<void> setVolume(double volume) async {
    if (!_ttsInitialized) return;
    await _tts.setVolume(volume);
  }

  void dispose() {
    if (_isInitialized) {
      _speech.cancel();
    }
    if (_ttsInitialized) {
      _tts.stop();
    }
  }

  static VoiceCommand parseCommand(String text) {
    final lower = text.toLowerCase().trim();

    // Add/Order patterns
    final addPatterns = [
      RegExp(r'add\s+(\d+)\s+(.+)', caseSensitive: false),
      RegExp(r'order\s+(\d+)\s+(.+)', caseSensitive: false),
      RegExp(r'give me\s+(\d+)\s+(.+)', caseSensitive: false),
      RegExp(r'i want\s+(\d+)\s+(.+)', caseSensitive: false),
      RegExp(r'get\s+(\d+)\s+(.+)', caseSensitive: false),
      RegExp(r'buy\s+(\d+)\s+(.+)', caseSensitive: false),
    ];

    for (final pattern in addPatterns) {
      final match = pattern.firstMatch(lower);
      if (match != null) {
        final quantity = int.tryParse(match.group(1) ?? '1') ?? 1;
        final drinkName = match.group(2)?.trim() ?? '';
        return VoiceCommand(
          type: VoiceCommandType.add,
          drinkName: drinkName,
          quantity: quantity.clamp(1, 99),
        );
      }
    }

    // Clear order patterns
    if (lower.contains('clear all') ||
        lower.contains('reset order') ||
        lower.contains('new order') ||
        lower == 'clear' ||
        lower == 'reset' ||
        lower == 'empty') {
      return VoiceCommand(type: VoiceCommandType.clear);
    }
    
    // Finalize/Checkout patterns
    if (lower.contains('finalize') ||
        lower.contains('complete order') ||
        lower.contains('pay now') ||
        lower.contains('checkout') ||
        lower.contains('pay') ||
        lower == 'checkout' ||
        lower == 'done') {
      return VoiceCommand(type: VoiceCommandType.finalize);
    }
    
    // Preview patterns
    if (lower.contains('preview') ||
        lower.contains('show invoice') ||
        lower.contains('view order') ||
        lower.contains('receipt') ||
        lower == 'preview') {
      return VoiceCommand(type: VoiceCommandType.preview);
    }

    // Search patterns
    final searchMatch = RegExp(r'search for (.+)', caseSensitive: false).firstMatch(lower);
    if (searchMatch != null) {
      return VoiceCommand(
        type: VoiceCommandType.search,
        drinkName: searchMatch.group(1)?.trim(),
      );
    }
    
    // Stock check patterns
    if (lower.contains('stock') || lower.contains('available')) {
      final drinkMatch = RegExp(r'stock of (.+)|(.+) stock|how many (.+)', caseSensitive: false).firstMatch(lower);
      if (drinkMatch != null) {
        final drinkName = drinkMatch.group(1) ?? drinkMatch.group(2) ?? drinkMatch.group(3);
        return VoiceCommand(
          type: VoiceCommandType.search,
          drinkName: drinkName?.trim(),
        );
      }
      return VoiceCommand(type: VoiceCommandType.search);
    }
    
    // Price check patterns
    if (lower.contains('price') || lower.contains('cost')) {
      final drinkMatch = RegExp(r'price of (.+)|(.+) price|how much is (.+)', caseSensitive: false).firstMatch(lower);
      if (drinkMatch != null) {
        final drinkName = drinkMatch.group(1) ?? drinkMatch.group(2) ?? drinkMatch.group(3);
        return VoiceCommand(
          type: VoiceCommandType.search,
          drinkName: drinkName?.trim(),
        );
      }
      return VoiceCommand(type: VoiceCommandType.search);
    }

    return VoiceCommand(type: VoiceCommandType.unknown, rawText: text);
  }
}

enum VoiceCommandType { 
  add, 
  clear, 
  finalize, 
  preview, 
  search, 
  unknown 
}

class VoiceCommand {
  final VoiceCommandType type;
  final String? drinkName;
  final int quantity;
  final String? rawText;

  VoiceCommand({
    required this.type,
    this.drinkName,
    this.quantity = 1,
    this.rawText,
  });
  
  @override
  String toString() {
    return 'VoiceCommand(type: $type, drinkName: $drinkName, quantity: $quantity)';
  }
}