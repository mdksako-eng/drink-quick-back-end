// services/payment_service.dart
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import '../config/api_config.dart';
import '../services/secure_storage_service.dart';

class PaymentService {
  static const String _baseUrl = ApiConfig.baseUrl;

  // ============================================================
  // 💳 PAYMENT METHODS
  // ============================================================

  /// Get company payment settings
  static Future<Map<String, dynamic>?> getCompanyPaymentSettings() async {
    try {
      final token = await SecureStorageService.getSessionToken();
      if (token == null) {
        print('❌ No auth token found');
        return null;
      }

      final response = await http.get(
        Uri.parse('$_baseUrl/api/company-settings'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data['success'] == true) {
          return data['data'];
        }
        return null;
      } else {
        print('❌ Failed to get payment settings: ${response.statusCode}');
        return null;
      }
    } catch (e) {
      print('❌ getCompanyPaymentSettings error: $e');
      return null;
    }
  }

  /// Update company payment settings (Manager only)
  static Future<bool> updateCompanyPaymentSettings(Map<String, dynamic> settings) async {
    try {
      final token = await SecureStorageService.getSessionToken();
      if (token == null) {
        print('❌ No auth token found');
        return false;
      }

      final response = await http.patch(
        Uri.parse('$_baseUrl/api/company-settings'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
        body: jsonEncode(settings),
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        return data['success'] == true;
      } else {
        print('❌ Failed to update payment settings: ${response.statusCode}');
        return false;
      }
    } catch (e) {
      print('❌ updateCompanyPaymentSettings error: $e');
      return false;
    }
  }

  // ============================================================
  // 🇨🇲 CAMERPAY — the company's own account (phase 3)
  // ============================================================

  /// Read this company's CamerPay connection state. The server only ever returns
  /// a MASKED view, so there is no secret to leak here.
  static Future<Map<String, dynamic>?> getCampaySettings() async {
    try {
      final token = await SecureStorageService.getSessionToken();
      if (token == null) {
        print('❌ No auth token found');
        return null;
      }

      final response = await http.get(
        Uri.parse('$_baseUrl/api/payment/campay-settings'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data['success'] == true) {
          return data['data'];
        }
        return null;
      }
      print('❌ Failed to get CamerPay settings: ${response.statusCode}');
      return null;
    } catch (e) {
      print('❌ getCampaySettings error: $e');
      return null;
    }
  }

  /// Connect, update, or disconnect this company's CamerPay account (manager only).
  ///
  /// [token] and [webhookSecret] are WRITE-ONLY: pass the real value to set or
  /// rotate them, or omit them to leave what the server already holds untouched —
  /// so a masked value shown in the UI can never overwrite a live secret.
  ///
  /// Returns the server's answer so the screen can explain a refusal instead of
  /// silently doing nothing: `vault_key_missing` means the server has no storage
  /// key, `token_required` means CamerPay cannot be enabled without a token, etc.
  static Future<Map<String, dynamic>> updateCampaySettings({
    bool? campayEnabled,
    String? token,
    String? webhookSecret,
    bool? rotateWebhookToken,
  }) async {
    try {
      final sessionToken = await SecureStorageService.getSessionToken();
      if (sessionToken == null) {
        return {'success': false, 'error': 'Not signed in'};
      }

      final body = <String, dynamic>{};
      if (campayEnabled != null) body['campayEnabled'] = campayEnabled;
      if (token != null) body['token'] = token;
      if (webhookSecret != null) body['webhookSecret'] = webhookSecret;
      if (rotateWebhookToken != null) {
        body['rotateWebhookToken'] = rotateWebhookToken;
      }

      final response = await http.patch(
        Uri.parse('$_baseUrl/api/payment/campay-settings'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $sessionToken',
        },
        body: jsonEncode(body),
      );

      final decoded = jsonDecode(response.body);
      if (decoded is Map && decoded['success'] == true) {
        return {'success': true, 'data': decoded['data']};
      }
      return {
        'success': false,
        'error': (decoded is Map ? decoded['error'] : null) ??
            'HTTP ${response.statusCode}',
      };
    } catch (e) {
      print('❌ updateCampaySettings error: $e');
      return {'success': false, 'error': e.toString()};
    }
  }

  // ============================================================
  // 💰 PAYMENT INITIATION
  // ============================================================

  /// Initiate a payment request
  static Future<Map<String, dynamic>> initiatePayment({
    required double amount,
    required String customerPhone,
    required String paymentMethod,
    required String orderId,
  }) async {
    try {
      final token = await SecureStorageService.getSessionToken();
      if (token == null) {
        return {
          'success': false,
          'error': 'Not authenticated',
        };
      }

      final response = await http.post(
        Uri.parse('$_baseUrl/api/payment/initiate'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
        body: jsonEncode({
          'amount': amount,
          'customerPhone': customerPhone,
          'paymentMethod': paymentMethod,
          'orderId': orderId,
        }),
      );

      final data = jsonDecode(response.body);
      
      if (response.statusCode == 200) {
        return data;
      } else {
        return {
          'success': false,
          'error': data['error'] ?? 'Payment initiation failed',
        };
      }
    } catch (e) {
      print('❌ initiatePayment error: $e');
      return {
        'success': false,
        'error': 'Network error: $e',
      };
    }
  }

  /// Check payment status
  static Future<Map<String, dynamic>> checkPaymentStatus(String transactionId) async {
    try {
      final token = await SecureStorageService.getSessionToken();
      if (token == null) {
        return {
          'success': false,
          'error': 'Not authenticated',
        };
      }

      final response = await http.get(
        Uri.parse('$_baseUrl/api/payment/status/$transactionId'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
      );

      final data = jsonDecode(response.body);
      
      if (response.statusCode == 200) {
        return data;
      } else {
        return {
          'success': false,
          'error': data['error'] ?? 'Failed to check payment status',
        };
      }
    } catch (e) {
      print('❌ checkPaymentStatus error: $e');
      return {
        'success': false,
        'error': 'Network error: $e',
      };
    }
  }

  /// Cancel a pending payment
  static Future<bool> cancelPayment(String transactionId) async {
    try {
      final token = await SecureStorageService.getSessionToken();
      if (token == null) {
        print('❌ No auth token found');
        return false;
      }

      final response = await http.post(
        Uri.parse('$_baseUrl/api/payment/cancel'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
        body: jsonEncode({
          'transactionId': transactionId,
        }),
      );

      final data = jsonDecode(response.body);
      return data['success'] == true;
    } catch (e) {
      print('❌ cancelPayment error: $e');
      return false;
    }
  }
}