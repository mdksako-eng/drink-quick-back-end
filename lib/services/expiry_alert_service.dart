// services/expiry_alert_service.dart
// Runs the batch-expiry check (see utils/expiry_alert_helper.dart) and announces
// each affected batch once, joined with its expected demand.
//
// The alert is raised locally (device notification history + system tray) and
// never written to Supabase. Each batch is announced once per day: the drinks
// carrying a batch date are checked in several places (app start, calculator,
// forecast screen), and the dedupe key is persisted so a rebuild or a second
// screen does not repeat the same warning.
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/drink_model.dart';
import '../models/forecast_model.dart';
import '../utils/expiry_alert_helper.dart';
import 'notification_service.dart';

class ExpiryAlertService {
  ExpiryAlertService._();

  static const String _prefsKey = 'expiry_alerts_last_run';

  /// True while a check is running (three screens can ask at once).
  static bool _running = false;

  /// Checks [drinks] for batches expiring within 30 days and notifies about
  /// those not already announced today.
  ///
  /// [forecast] is optional: without it the alert still fires, just without the
  /// demand / suggested-order numbers.
  ///
  /// Returns the alerts that were announced (handy for tests and callers that
  /// want to show a banner).
  static Future<List<ExpiryAlert>> check({
    required List<Drink> drinks,
    ForecastResult? forecast,
    DateTime? now,
  }) async {
    if (_running) return const [];
    _running = true;
    try {
      final alerts = computeExpiryAlerts(drinks: drinks, forecast: forecast);
      if (alerts.isEmpty) return const [];

      final prefs = await SharedPreferences.getInstance();
      final today = _dayKey(now ?? DateTime.now());
      final seen = <String>{};
      for (final key in prefs.getStringList(_prefsKey) ?? const <String>[]) {
        if (key.startsWith('$today::')) seen.add(key);
      }

      final announced = <ExpiryAlert>[];
      final recorded = <String>[];
      for (final alert in alerts) {
        final entry = '$today::${alert.dedupeKey}';
        if (seen.contains(entry)) continue;
        recorded.add(entry);
        announced.add(alert);
      }

      if (announced.isEmpty) return const [];

      // Keep only today's markers so the list cannot grow forever.
      final todayEntries = <String>[
        ...(prefs.getStringList(_prefsKey) ?? const <String>[])
            .where((k) => k.startsWith('$today::')),
        ...recorded,
      ];
      await prefs.setStringList(_prefsKey, todayEntries);

      for (final alert in announced) {
        NotificationService().showExpirySoon(
          drinkName: alert.drinkName,
          daysLeft: alert.daysLeft,
          expired: alert.isExpired,
          forecastDemand: alert.forecastDemand,
          recommendedOrder: alert.recommendedOrder,
        );
      }
      debugPrint('⏰ ${announced.length} batch expiry alert(s) raised');
      return announced;
    } catch (e) {
      debugPrint('⚠️ Expiry alert check failed: $e');
      return const [];
    } finally {
      _running = false;
    }
  }

  /// `yyyy-MM-dd` for the given day — the dedupe bucket.
  static String _dayKey(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-'
      '${d.month.toString().padLeft(2, '0')}-'
      '${d.day.toString().padLeft(2, '0')}';

  @visibleForTesting
  static Future<void> resetForTesting() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_prefsKey);
    } catch (_) {}
  }
}