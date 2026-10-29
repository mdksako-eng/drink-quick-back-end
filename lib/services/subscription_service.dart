// services/subscription_service.dart
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import '../config/api_config.dart';
import '../models/subscription_model.dart';
import '../services/secure_storage_service.dart';
// A refusal is shown in our own words, never the provider's (see the helper).
import '../utils/payment_error_helper.dart';

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
  /// PayPal).
  ///
  /// One hosted page per rail, and the plan activates only when the server
  /// confirms a REAL (non-sandbox) transaction — a sandbox payment can never hand
  /// out a paid plan. [channel] is the rail the payer picked ('mtn' / 'orange' /
  /// 'card'); anything else means "let the customer choose on CamerPay's page".
  static Future<Map<String, dynamic>?> campayInitiate({
    required String plan,
    String? channel,
    String? customerPhone,
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
        body: jsonEncode({
          'plan': plan,
          if (rail != null) 'rail': rail,
          // The number to charge. Sent only when the payer typed one, so the server
          // falls back to the profile phone and, failing that, lets CamerPay ask.
          if (customerPhone != null && customerPhone.trim().isNotEmpty)
            'customerPhone': customerPhone.trim(),
        }),
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data['success'] == true) {
          return Map<String, dynamic>.from(data['data'] ?? {});
        }
      } else {
        // A refusal carries a machine-readable code; the app renders its own
        // sentence. The provider's own words travel in `providerMessage` for the log
        // and are shown only where they are actionable (see PaymentErrorHelper).
        final data = _errorBody(response.body);
        throw PaymentFailure(
          code: (data['code'] ?? data['error'] ?? PaymentErrorHelper.unknownCode)
              .toString(),
          providerMessage: data['providerMessage']?.toString(),
          providerCode: data['providerCode']?.toString(),
          accountLevel: data['accountLevel'] == true,
        );
      }
      return null;
    } catch (e) {
      if (e is PaymentFailure) {
        // The code is what we act on; the provider's sentence is for support.
        debugPrint(
          'SubscriptionService.campayInitiate refused: ${e.code}'
          '${e.providerCode == null ? '' : ' (${e.providerCode})'}'
          '${e.providerMessage == null ? '' : ' — ${e.providerMessage}'}',
        );
      } else {
        debugPrint('SubscriptionService.campayInitiate error: $e');
      }
      rethrow;
    }
  }

  /// A refusal body, even when it is not JSON (a proxy error page, a timeout body):
  /// an unreadable body must not turn into a confusing parse error on top of the
  /// refusal we are trying to explain.
  static Map<String, dynamic> _errorBody(String body) {
    try {
      final decoded = jsonDecode(body);
      if (decoded is Map<String, dynamic>) return decoded;
    } catch (_) {
      // fall through
    }
    return const {};
  }

  /// Rail the caller picked → CamerPay's rail name, so tapping MTN lands on MTN,
  /// Orange on Orange and Card on card instead of CamerPay's menu.
  ///
  /// Accepts the app's rail values ('mtn' / 'orange' / 'card') and tolerates the
  /// raw slugs an older build sent ('cm.mtn' / 'cm.orange'). Anything unknown
  /// returns null, which means "do not lock" and the payer chooses on CamerPay's
  /// own page.
  static String? _campayRailFor(String? channel) {
    switch (channel) {
      case 'cm.mtn':
      case 'mtn':
        return 'mtn';
      case 'cm.orange':
      case 'orange':
        return 'orange';
      case 'card':
      case 'cm.card':
      case 'stripe':
      case 'visa':
        return 'card';
      default:
        return null;
    }
  }

  /// Poll a CamerPay subscription payment. Returns { active, status, reason, ... }.
  static Future<Map<String, dynamic>?> campayStatus({
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
