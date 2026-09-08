// services/subscription_service.dart
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import '../config/api_config.dart';
import '../models/subscription_model.dart';
import '../services/secure_storage_service.dart';

class SubscriptionService {
  /// Fetch the current plan/status for the logged-in company.
  static Future<SubscriptionInfo?> getStatus() async {
    try {
      final token = await SecureStorageService.getSessionToken();
      if (token == null) return null;

      final response = await http.get(
        Uri.parse(ApiConfig.subscriptionStatus),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data['success'] == true && data['data'] != null) {
          return SubscriptionInfo.fromJson(data['data']);
        }
      }
      return null;
    } catch (e) {
      debugPrint('SubscriptionService.getStatus error: $e');
      return null;
    }
  }

  /// Start a card payment (Flutterwave) and return the checkout URL.
  static Future<Map<String, dynamic>?> initiate({
    required String plan,
  }) async {
    try {
      final token = await SecureStorageService.getSessionToken();
      if (token == null) return null;

      final response = await http.post(
        Uri.parse(ApiConfig.subscriptionInitiate),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
        body: jsonEncode({'plan': plan, 'provider': 'flutterwave'}),
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data['success'] == true) {
          return Map<String, dynamic>.from(data['data'] ?? {});
        }
      }
      return null;
    } catch (e) {
      debugPrint('SubscriptionService.initiate error: $e');
      return null;
    }
  }

  /// Initiate a mobile-money (MTN/Orange) subscription payment.
  static Future<Map<String, dynamic>?> momoInitiate({
    required String plan,
    required String provider,
    required String customerPhone,
  }) async {
    try {
      final token = await SecureStorageService.getSessionToken();
      if (token == null) return null;

      final response = await http.post(
        Uri.parse(ApiConfig.subscriptionMomoInitiate),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
        body: jsonEncode({
          'plan': plan,
          'provider': provider,
          'customerPhone': customerPhone,
        }),
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data['success'] == true) {
          return Map<String, dynamic>.from(data['data'] ?? {});
        }
        // Surface backend validation errors (e.g. invalid phone).
        if (data['error'] != null) {
          throw Exception(data['error']);
        }
      }
      return null;
    } catch (e) {
      debugPrint('SubscriptionService.momoInitiate error: $e');
      rethrow;
    }
  }

  /// Confirm a mobile-money payment and activate the plan.
  static Future<bool> momoConfirm({
    required String reference,
    required String plan,
  }) async {
    try {
      final token = await SecureStorageService.getSessionToken();
      if (token == null) return false;

      final response = await http.post(
        Uri.parse(ApiConfig.subscriptionMomoConfirm),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
        body: jsonEncode({'reference': reference, 'plan': plan}),
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        return data['success'] == true && data['data']?['active'] == true;
      }
      return false;
    } catch (e) {
      debugPrint('SubscriptionService.momoConfirm error: $e');
      return false;
    }
  }

  /// Verify a payment and activate the plan.
  static Future<bool> verify({
    required String transactionId,
    required String plan,
  }) async {
    try {
      final token = await SecureStorageService.getSessionToken();
      if (token == null) return false;

      final uri = Uri.parse(ApiConfig.subscriptionVerify).replace(queryParameters: {
        'transaction_id': transactionId,
        'plan': plan,
      });

      final response = await http.get(
        uri,
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        return data['data']?['active'] == true;
      }
      return false;
    } catch (e) {
      debugPrint('SubscriptionService.verify error: $e');
      return false;
    }
  }
}
