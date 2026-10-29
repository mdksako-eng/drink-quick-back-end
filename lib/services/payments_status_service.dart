// services/payments_status_service.dart
// Answers one honest question: are subscription payments LIVE, or still in test
// mode? The backend already reports it (`accountDeclaredLive`, `liveReady` in the
// CamerPay health endpoint); this service surfaces it to the UI so a user is
// never left believing a real payment was taken while the account is in sandbox.
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../config/api_config.dart';

class PaymentsStatus {
  const PaymentsStatus({
    required this.mode,
    required this.liveReady,
    this.providerConfigured = false,
    this.hint,
  });

  /// 'live' or 'test'.
  final String mode;
  final bool liveReady;
  /// True when the payment account (CamerPay) has its credentials set.
  final bool providerConfigured;
  final String? hint;

  /// True only when a rail can take REAL money.
  ///
  /// CamerPay cannot reveal sandbox-vs-live from its token — the account declares it
  /// (`CAMERPAY_ACCOUNT_LIVE=true`, reported as `accountDeclaredLive`), and the
  /// backend folds that into `liveReady`. So `liveReady` IS the honest answer; the
  /// old rule also demanded `mode == 'live'`, and since the CamerPay payload has no
  /// `mode` field at all, that kept the app on "TEST" forever.
  bool get isLive => liveReady;

  /// Shown in the subscription screen while the rails are still in test mode.
  String get shortLabel => isLive ? 'LIVE' : 'TEST';

  static const PaymentsStatus unknown = PaymentsStatus(
    mode: 'unknown',
    liveReady: false,
  );

  factory PaymentsStatus.fromJson(Map<String, dynamic> json) {
    // CamerPay payload: provider/configured/accountDeclaredLive/liveReady/hint.
    // There is no `mode` field to read — the token cannot reveal it — so the
    // operator's declaration (`accountDeclaredLive`) and `liveReady` decide.
    final declaredLive = json['accountDeclaredLive'] == true;
    final liveReady = json['liveReady'] == true;
    return PaymentsStatus(
      mode: json['mode']?.toString() ??
          (liveReady || declaredLive ? 'live' : 'test'),
      liveReady: liveReady,
      providerConfigured: json['configured'] == true,
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
