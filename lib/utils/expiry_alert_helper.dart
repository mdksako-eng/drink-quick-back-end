// utils/expiry_alert_helper.dart
// Batch-expiry alerts joined with the demand forecast.
//
// A drink whose batch expires within 30 days is not just a waste risk: the
// forecast tells us how much of it we expect to sell in the coming days, so the
// alert can say "expires in 4 days, expected demand 18 units — push this stock".
// Pure functions only, so this is unit tested.
import '../models/drink_model.dart';
import '../models/forecast_model.dart';

/// Number of days before expiry that counts as "expiring soon".
const int kExpiryAlertWindowDays = 30;

class ExpiryAlert {
  final String drinkId;
  final String drinkName;

  /// Expiry day (midnight) of the batch.
  final DateTime expiryDate;

  /// Days until expiry; negative when the batch is already past its date.
  final int daysLeft;
  final bool isExpired;

  /// Units currently in stock for this drink.
  final int currentStock;

  /// Expected demand over the forecast horizon (0 when no forecast was given).
  final double forecastDemand;

  /// Suggested order quantity from the forecast (0 when there is no forecast).
  final int recommendedOrder;
  final double confidence;

  const ExpiryAlert({
    required this.drinkId,
    required this.drinkName,
    required this.expiryDate,
    required this.daysLeft,
    required this.isExpired,
    required this.currentStock,
    this.forecastDemand = 0,
    this.recommendedOrder = 0,
    this.confidence = 0,
  });

  /// Identifies the batch, so the same batch is only announced once.
  String get dedupeKey =>
      '$drinkId|${expiryDate.toIso8601String().split('T').first}';
}

/// Drinks that expire within [withinDays] days (or are already expired), each
/// joined with its forecast row when a forecast is supplied.
///
/// Sorted by urgency (soonest expiry first).
List<ExpiryAlert> computeExpiryAlerts({
  required List<Drink> drinks,
  ForecastResult? forecast,
  int withinDays = kExpiryAlertWindowDays,
}) {
  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day);

  // Match the forecast by name (the forecast engine aggregates per drink name).
  final byName = <String, ForecastItem>{};
  for (final item in forecast?.items ?? const <ForecastItem>[]) {
    byName[item.drinkName.trim().toLowerCase()] = item;
  }

  final alerts = <ExpiryAlert>[];
  for (final drink in drinks) {
    final expiry = drink.expiryDate;
    if (expiry == null) continue;

    final day = DateTime(expiry.year, expiry.month, expiry.day);
    final daysLeft = day.difference(today).inDays;
    final expired = daysLeft < 0;
    if (!expired && daysLeft > withinDays) continue;

    final match = byName[drink.name.trim().toLowerCase()];
    alerts.add(ExpiryAlert(
      drinkId: drink.id,
      drinkName: drink.name,
      expiryDate: day,
      daysLeft: daysLeft,
      isExpired: expired,
      currentStock: drink.currentStock,
      forecastDemand: match?.forecastDemand ?? 0,
      recommendedOrder: match?.recommendedOrder ?? 0,
      confidence: match?.confidence ?? 0,
    ));
  }

  alerts.sort((a, b) => a.daysLeft.compareTo(b.daysLeft));
  return alerts;
}

/// Localized one-line summary used by notifications and the on-screen banner.
String expiryAlertMessage(ExpiryAlert alert, String Function(String) t) {
  final when = alert.isExpired
      ? t('expiryAlreadyExpired')
      : '${alert.daysLeft} ${t('expiryDaysLeft')}';
  final buffer = StringBuffer('${alert.drinkName}: $when');
  if (alert.forecastDemand > 0) {
    buffer.write(' • ${t('expiryExpectedDemand')}: '
        '${alert.forecastDemand.toStringAsFixed(1)}');
  }
  if (alert.recommendedOrder > 0) {
    buffer.write(' • ${t('expirySuggestedOrder')}: ${alert.recommendedOrder}');
  }
  return buffer.toString();
}