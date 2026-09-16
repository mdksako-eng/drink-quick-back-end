// services/groq_service.dart
import 'dart:convert';
import 'package:http/http.dart' as http;
import '../config/api_config.dart';
import 'secure_storage_service.dart';

/// Groq-backed AI chat that proxies through the backend.
/// The API key NEVER lives in the app — the backend uses its own GROQ_API_KEY.
class GroqService {
  static const String _chatUrl = '${ApiConfig.apiBase}/ai/chat';
  static const String _visionUrl = '${ApiConfig.apiBase}/ai/vision';

  /// Sends a photo (base64 or data URL) to the backend vision model and returns
  /// its reading of the order, including the machine-readable ORDER_JSON block.
  Future<String> analyzeImage({
    required String base64Image,
    List<String> drinks = const [],
    String prompt = '',
  }) async {
    final token = await SecureStorageService.getSessionToken();
    if (token == null || token.isEmpty) {
      return 'Please sign in to use the AI assistant.';
    }

    try {
      final response = await http
          .post(
            Uri.parse(_visionUrl),
            headers: {
              'Content-Type': 'application/json',
              'Authorization': 'Bearer $token',
            },
            body: jsonEncode({
              'image': base64Image,
              'drinks': drinks,
              'prompt': prompt,
            }),
          )
          .timeout(const Duration(seconds: 60));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final content = data['content']?.toString().trim() ?? '';
        return content.isEmpty ? 'No response' : content;
      }
      if (response.statusCode == 401) {
        return 'Session expired. Please sign in again.';
      }
      if (response.statusCode == 403) {
        return 'Image reading is available on the Pro plan.';
      }
      try {
        final data = jsonDecode(response.body);
        return data['error']?.toString() ?? 'Could not read the image.';
      } catch (_) {
        return 'Could not read the image.';
      }
    } catch (e) {
      if (e.toString().contains('Timeout')) {
        return 'The image took too long to analyse. Please try again.';
      }
      return 'Connection error: Unable to reach AI service. Please check your internet.';
    }
  }

  Future<String> getResponse(String prompt,
      {List<Map<String, String>>? history}) async {
    // 🔐 Send only our own session token; the backend adds the Groq key.
    final token = await SecureStorageService.getSessionToken();
    if (token == null || token.isEmpty) {
      return 'Please sign in to use the AI assistant.';
    }

    try {
      final response = await http.post(
        Uri.parse(_chatUrl),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
        body: jsonEncode({
          'prompt': prompt,
          'history': history ?? [],
        }),
      ).timeout(const Duration(seconds: 30));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final content = data['content']?.toString().trim() ?? '';
        return content.isEmpty ? 'No response' : content;
      } else if (response.statusCode == 401) {
        return 'Session expired. Please sign in again.';
      } else {
        final data = jsonDecode(response.body);
        final msg = data['error']?.toString() ?? 'Request failed';
        return msg;
      }
    } catch (e) {
      if (e.toString().contains('Timeout')) {
        return 'Request timeout. Please check your internet connection and try again.';
      }
      return 'Connection error: Unable to reach AI service. Please check your internet.';
    }
  }

  Future<String> getSimpleResponse(String prompt) async {
    return getResponse(prompt);
  }
}
