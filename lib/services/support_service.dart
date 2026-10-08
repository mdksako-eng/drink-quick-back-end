// services/support_service.dart
// Files a bug report or complaint to POST /api/support/reports.
//
// The context block is built HERE, never typed by the user: a report saying only
// "it does not work" cannot be investigated, while company + user + platform +
// version + screen + role usually answers the question before anyone replies.
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import '../config/api_config.dart';
import 'secure_storage_service.dart';

class SupportService {
  SupportService._();

  /// Kept in step with the version shown in the drawer footer.
  static const String appVersion = '1.1.0';

  /// What the user was doing at the time. Only these keys are sent (and the server
  /// keeps only these keys, bounded), so this cannot become a data dump.
  static Map<String, String> buildContext({
    String? screen,
    String? role,
    String? locale,
  }) {
    // kIsWeb + defaultTargetPlatform are web-safe; dart:io's Platform is not.
    final platform = kIsWeb ? 'web' : defaultTargetPlatform.name;
    return <String, String>{
      'platform': platform,
      'appVersion': appVersion,
      if (screen != null && screen.isNotEmpty) 'screen': screen,
      if (role != null && role.isNotEmpty) 'role': role,
      if (locale != null && locale.isNotEmpty) 'locale': locale,
    };
  }

  /// Send the report.
  /// @returns {success: bool, reference: String, error: String}
  static Future<Map<String, dynamic>> sendReport({
    required String category,
    required String message,
    String subject = '',
    Map<String, String>? context,
  }) async {
    try {
      final token = await SecureStorageService.getSessionToken();
      if (token == null) {
        return {'success': false, 'error': 'Not signed in'};
      }

      final response = await http.post(
        Uri.parse('${ApiConfig.apiBase}/support/reports'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
        body: jsonEncode({
          'category': category,
          'subject': subject,
          'message': message,
          if (context != null && context.isNotEmpty) 'context': context,
        }),
      );

      final decoded = jsonDecode(response.body);
      if (response.statusCode == 200 && decoded is Map && decoded['success'] == true) {
        final data = decoded['data'] is Map
            ? Map<String, dynamic>.from(decoded['data'])
            : <String, dynamic>{};
        return {'success': true, 'reference': (data['reference'] ?? '').toString()};
      }

      final error = decoded is Map
          ? (decoded['error'] ?? 'Something went wrong')
          : 'HTTP ${response.statusCode}';
      return {'success': false, 'error': error.toString()};
    } catch (e) {
      debugPrint('SupportService.sendReport error: $e');
      return {'success': false, 'error': 'Network error: $e'};
    }
  }
}
