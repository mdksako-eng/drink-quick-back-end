// providers/plan_provider.dart
import 'package:flutter/foundation.dart';
import '../models/subscription_model.dart';
import '../services/subscription_service.dart';

class PlanProvider extends ChangeNotifier {
  SubscriptionInfo _info = const SubscriptionInfo();
  bool _loading = false;

  /// True once a plan fetch has completed (successfully or not). The
  /// subscription gate uses this to know it is safe to decide whether to show
  /// the plans, instead of judging on the default ('free') placeholder.
  bool _hasLoaded = false;

  SubscriptionInfo get info => _info;
  bool get loading => _loading;
  bool get hasLoaded => _hasLoaded;
  String get plan => _info.plan;
  bool get isActive => _info.isActive;

  static const Map<String, String> _featurePlans = {
    'staff': 'starter',
    'reports': 'starter',
    'analytics': 'pro',
    'forecast': 'pro',
    'scanner': 'pro',
    'printing': 'pro',
    'ai': 'pro',
    'inbox': 'pro',
  };

  int _rank(String plan) {
    switch (plan.toLowerCase()) {
      case 'pro':
        return 2;
      case 'starter':
        return 1;
      default:
        return 0;
    }
  }

  /// Whether the current plan grants access to [feature].
  bool canAccess(String feature) {
    final required = _featurePlans[feature] ?? 'pro';
    return _rank(_info.plan) >= _rank(required);
  }

  /// Returns a human price for a plan (e.g. "5,000 XAF") or ''.
  String priceLabel(String plan) {
    final p = _info.prices[plan];
    if (p is! Map) return '';
    final amount = num.tryParse('${p['amount']}') ?? 0;
    if (amount == 0) return '';
    final formatted = amount.toInt().toString().replaceAllMapped(
          RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'),
          (m) => '${m[1]},',
        );
    return '$formatted ${p['currency'] ?? 'XAF'}';
  }

  Future<void> refresh() async {
    _loading = true;
    notifyListeners();
    try {
      final info = await SubscriptionService.getStatus();
      if (info != null) {
        _info = info;
      }
    } finally {
      _loading = false;
      // Mark the plan as resolved even when the fetch failed: the gate then
      // falls back to the local/default state instead of blocking the app.
      _hasLoaded = true;
      notifyListeners();
    }
  }

  /// Begin a card payment for [plan]; returns the checkout URL (or null).
  Future<Map<String, dynamic>?> initiate(String plan) async {
    final result = await SubscriptionService.initiate(plan: plan);
    return result;
  }

  /// Begin a mobile-money (MTN/Orange) payment; returns the initiate data.
  Future<Map<String, dynamic>?> momoInitiate({
    required String plan,
    required String provider,
    required String customerPhone,
  }) {
    return SubscriptionService.momoInitiate(
      plan: plan,
      provider: provider,
      customerPhone: customerPhone,
    );
  }

  /// Poll mobile-money payment status; refreshes state when it becomes active.
  Future<Map<String, dynamic>?> momoStatus({required String reference}) async {
    final result = await SubscriptionService.momoStatus(reference: reference);
    if (result?['active'] == true) {
      await refresh();
    }
    return result;
  }

  /// Confirm a mobile-money payment and refresh local state.
  Future<bool> momoConfirm({
    required String reference,
    required String plan,
  }) async {
    final ok = await SubscriptionService.momoConfirm(
      reference: reference,
      plan: plan,
    );
    if (ok) await refresh();
    return ok;
  }

  /// Begin a Notch Pay payment (unified MoMo/OM/card); returns initiate data.
  Future<Map<String, dynamic>?> notchpayInitiate({
    required String plan,
    String? channel,
  }) {
    return SubscriptionService.notchpayInitiate(plan: plan, channel: channel);
  }

  /// Poll Notch Pay payment status; refreshes state when it becomes active.
  Future<Map<String, dynamic>?> notchpayStatus({required String reference}) async {
    final result = await SubscriptionService.notchpayStatus(reference: reference);
    if (result?['active'] == true) {
      await refresh();
    }
    return result;
  }

  /// Verify a payment and refresh local state.
  Future<bool> verify({required String transactionId, required String plan}) async {
    final ok = await SubscriptionService.verify(
      transactionId: transactionId,
      plan: plan,
    );
    if (ok) await refresh();
    return ok;
  }
}
