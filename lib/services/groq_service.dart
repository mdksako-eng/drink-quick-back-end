// services/groq_service.dart
import 'dart:convert';
import 'package:http/http.dart' as http;
import '../config/api_config.dart';
import 'secure_storage_service.dart';

/// Groq-backed AI chat that proxies through the backend.
/// The API key NEVER lives in the app — the backend uses its own GROQ_API_KEY.
class GroqService {
  static const String _chatUrl = '${ApiConfig.apiBase}/ai/chat';

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
