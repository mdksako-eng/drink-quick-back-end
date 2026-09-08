// models/subscription_model.dart
// Subscription (freemium) plan state for a company.

class SubscriptionInfo {
  final String plan; // 'free' | 'starter' | 'pro'
  final String status; // 'none' | 'active' | 'expired' | 'cancelled'
  final DateTime? expiresAt;

  const SubscriptionInfo({
    this.plan = 'free',
    this.status = 'none',
    this.expiresAt,
  });

  bool get isActive =>
      status == 'active' && (expiresAt == null || expiresAt!.isAfter(DateTime.now()));

  factory SubscriptionInfo.fromJson(Map<String, dynamic> json) {
    final expiresRaw = json['expiresAt'];
    return SubscriptionInfo(
      plan: json['plan']?.toString().toLowerCase() ?? 'free',
      status: json['status']?.toString().toLowerCase() ?? 'none',
      expiresAt: expiresRaw != null ? DateTime.tryParse('$expiresRaw') : null,
    );
  }
}
