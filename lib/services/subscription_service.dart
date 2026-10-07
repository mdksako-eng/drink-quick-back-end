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

  /// Poll the mobile-money payment status. Returns:
  ///   { active: bool, status: 'pending'|'failed'|..., auto: bool }
  static Future<Map<String, dynamic>?> momoStatus({
    required String reference,
  }) async {
    try {
      final token = await SecureStorageService.getSessionToken();
      if (token == null) return null;

      final uri = Uri.parse(ApiConfig.subscriptionMomoStatus)
          .replace(queryParameters: {'reference': reference});

      final response = await http.get(
        uri,
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data['success'] == true) {
          return Map<String, dynamic>.from(data['data'] ?? {});
        }
      }
      return null;
    } catch (e) {
      debugPrint('SubscriptionService.momoStatus error: $e');
      return null;
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

  /// Start a subscription payment through **CamerPay** (Mobile Money, card,
  /// PayPal). The method names are kept for now so the screen needs no change;
  /// they are renamed when the Notch Pay code is deleted.
  ///
  /// CamerPay replaces the old Notch Pay checkout: one hosted page per rail, and
  /// the plan activates only when the server confirms a REAL (non-sandbox)
  /// transaction — a sandbox payment can never hand out a paid plan.
  /// [channel] keeps the caller's rail slug ('cm.mtn' / 'cm.orange'); anything
  /// else means "let the customer choose on CamerPay's page".
  static Future<Map<String, dynamic>?> notchpayInitiate({
    required String plan,
    String? channel,
  }) async {
    try {
      final token = await SecureStorageService.getSessionToken();
      if (token == null) return null;

      final rail = _campayRailFor(channel);
      final response = await http.post(
        Uri.parse(ApiConfig.subscriptionCampayInitiate),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
        body: jsonEncode({'plan': plan, if (rail != null) 'rail': rail}),
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data['success'] == true) {
          return Map<String, dynamic>.from(data['data'] ?? {});
        }
      } else {
        // 402 (KYC / plan quota) and 503 (not ready) carry a message worth showing.
        final data = jsonDecode(response.body);
        if (data is Map && data['message'] != null) {
          throw Exception(data['message']);
        }
        if (data is Map && data['error'] != null) throw Exception(data['error']);
      }
      return null;
    } catch (e) {
      debugPrint('SubscriptionService.campayInitiate error: $e');
      rethrow;
    }
  }

  /// Rail slug the caller used ('cm.mtn' / 'cm.orange') → CamerPay's rail name.
  static String? _campayRailFor(String? channel) {
    switch (channel) {
      case 'cm.mtn':
        return 'mtn';
      case 'cm.orange':
        return 'orange';
      default:
        return null; // card / anything else: the payer chooses on CamerPay.
    }
  }

  /// CamerPay publishes no per-rail availability list — every method the account
  /// can charge is offered on its own page — so this returns null, which the
  /// screen already treats as "unknown: keep every rail enabled".
  static Future<Map<String, dynamic>?> notchpayChannels() async => null;

  /// Poll a CamerPay subscription payment. Returns { active, status, reason, ... }.
  static Future<Map<String, dynamic>?> notchpayStatus({
    required String reference,
  }) async {
    try {
      final token = await SecureStorageService.getSessionToken();
      if (token == null) return null;

      final uri = Uri.parse(ApiConfig.subscriptionCampayStatus)
          .replace(queryParameters: {'reference': reference});

      final response = await http.get(
        uri,
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data['success'] == true) {
          return Map<String, dynamic>.from(data['data'] ?? {});
        }
      }
      return null;
    } catch (e) {
      debugPrint('SubscriptionService.campayStatus error: $e');
      return null;
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
