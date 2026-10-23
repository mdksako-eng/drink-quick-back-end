// providers/plan_provider.dart
import 'package:flutter/foundation.dart';
import '../models/subscription_model.dart';
import '../services/subscription_service.dart';
import '../services/voice_service.dart';
import '../utils/plan_gate_logic.dart';
import '../utils/voice_access.dart';

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
  ///
  /// A platform administrator is let through regardless of the plan — the backend
  /// already does exactly that in `requirePlan`, so the app must not be stricter
  /// than the server it is talking to.
  bool canAccess(String feature) {
    final required = _featurePlans[feature] ?? 'pro';
    return featureAccessAllowed(
      isAdmin: _isAdmin,
      planGrants: _rank(_info.plan) >= _rank(required),
    );
  }

  /// 🔐 True when the signed-in user is a platform administrator.
  ///
  /// Pushed in after login (see `main.dart`) because this provider resolves the
  /// plan only and never reads the auth state itself.
  bool _isAdmin = false;
  bool get isAdmin => _isAdmin;

  /// Called right after login / session restore, before the plan is fetched.
  void setIsAdmin(bool isAdmin) {
    if (_isAdmin == isAdmin) return;
    _isAdmin = isAdmin;
    notifyListeners();
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
      _syncVoiceEntitlement();
      notifyListeners();
    }
  }

  /// 🔒 Tells `VoiceService` whether this plan includes voice.
  ///
  /// Voice is a paid capability that ships OFF, so an unresolved plan (boot, a
  /// failed first fetch) is a "no". A later successful fetch flips it on without a
  /// restart; a downgrade flips it off immediately.
  void _syncVoiceEntitlement() {
    VoiceService.setPlanAllowsVoice(voiceAllowedForPlan(
      planResolved: _hasLoaded,
      grantsAiFeature: canAccess('ai'),
    ));
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
    String? customerPhone,
  }) {
    return SubscriptionService.notchpayInitiate(
        plan: plan, channel: channel, customerPhone: customerPhone);
  }

  /// Which rails can be charged right now (card / MTN / Orange), as reported by
  /// the server from the payment provider's own channel list.
  Future<Map<String, dynamic>?> notchpayChannels() =>
      SubscriptionService.notchpayChannels();

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
