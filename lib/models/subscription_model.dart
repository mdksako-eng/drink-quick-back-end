// models/subscription_model.dart
// Subscription (freemium) plan state for a company.

class SubscriptionInfo {
  final String plan; // 'free' | 'starter' | 'pro'
  final String status; // 'none' | 'active' | 'expired' | 'cancelled'
  final DateTime? expiresAt;
  final Map<String, dynamic> prices; // e.g. { pro: { amount, currency, label } }

  const SubscriptionInfo({
    this.plan = 'free',
    this.status = 'none',
    this.expiresAt,
    this.prices = const {},
  });

  bool get isActive =>
      status == 'active' && (expiresAt == null || expiresAt!.isAfter(DateTime.now()));

  factory SubscriptionInfo.fromJson(Map<String, dynamic> json) {
    final expiresRaw = json['expiresAt'];
    final pricesRaw = json['prices'];
    return SubscriptionInfo(
      plan: json['plan']?.toString().toLowerCase() ?? 'free',
      status: json['status']?.toString().toLowerCase() ?? 'none',
      expiresAt: expiresRaw != null ? DateTime.tryParse('$expiresRaw') : null,
      prices: pricesRaw is Map ? Map<String, dynamic>.from(pricesRaw) : const {},
    );
  }
}
