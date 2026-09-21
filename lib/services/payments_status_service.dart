// services/payments_status_service.dart
// Answers one honest question: are subscription payments LIVE, or still in test
// mode? The backend already reports it (`mode`, `liveReady` in the Notch Pay
// health endpoint); this service surfaces it to the UI so a user is never left
// believing a real payment was taken when the platform is still in test mode.
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../config/api_config.dart';

class PaymentsStatus {
  const PaymentsStatus({
    required this.mode,
    required this.liveReady,
    this.notchPayConfigured = false,
    this.hint,
  });

  /// 'live' or 'test'.
  final String mode;
  final bool liveReady;
  final bool notchPayConfigured;
  final String? hint;

  bool get isLive => mode.toLowerCase() == 'live' && liveReady;

  /// Shown in the subscription screen while the rails are still in test mode.
  String get shortLabel => isLive ? 'LIVE' : 'TEST';

  static const PaymentsStatus unknown = PaymentsStatus(
    mode: 'unknown',
    liveReady: false,
  );

  factory PaymentsStatus.fromJson(Map<String, dynamic> json) {
    return PaymentsStatus(
      mode: (json['mode'] ?? json['notchpayMode'] ?? 'unknown').toString(),
      liveReady: json['liveReady'] == true,
      notchPayConfigured: json['notchpayConfigured'] == true,
      hint: json['hint']?.toString(),
    );
  }
}

class PaymentsStatusService {
  PaymentsStatusService._();

  static PaymentsStatus? _cache;

  /// Cached in memory for the session; [forceRefresh] re-checks the server.
  static Future<PaymentsStatus> load({bool forceRefresh = false}) async {
    if (!forceRefresh && _cache != null) return _cache!;

    try {
      final response = await http
          .get(Uri.parse(ApiConfig.subscriptionPaymentsHealth))
          .timeout(const Duration(seconds: 12));
      if (response.statusCode != 200) {
        debugPrint('⚠️ Payments health HTTP ${response.statusCode}');
        return _cache ?? PaymentsStatus.unknown;
      }
      final decoded = json.decode(response.body);
      final data = decoded is Map<String, dynamic>
          ? (decoded['data'] is Map ? decoded['data'] as Map : decoded)
          : <String, dynamic>{};
      final status = PaymentsStatus.fromJson(Map<String, dynamic>.from(data));
      _cache = status;
      return status;
    } catch (e) {
      debugPrint('⚠️ Payments health error: $e');
      return _cache ?? PaymentsStatus.unknown;
    }
  }

  @visibleForTesting
  static void resetCache() => _cache = null;
}
