// utils/forecast_helper.dart
// Deterministic demand forecasting: moving average + weekly seasonality
// + holiday/event multipliers. Works fully offline.
import '../models/forecast_model.dart';
import '../models/inventory_model.dart';

ForecastResult computeForecast({
  required List<InventoryTransaction> transactions,
  required List<InventoryItem> inventory,
  int horizonDays = 7,
  int historyDays = 90,
  List<EventDay> events = const [],
}) {
  final now = DateTime.now();
  final historyStart = now.subtract(Duration(days: historyDays));
  final endInclusive = now.add(const Duration(days: 1));
  final midPoint = historyStart.add(Duration(days: historyDays ~/ 2));

  final names = <String>{};
  final demand = <String, List<InventoryTransaction>>{};
  for (final item in inventory) {
    names.add(item.drinkName);
  }
  for (final t in transactions) {
    if (!t.isOutgoing) continue;
    names.add(t.drinkName);
    demand.putIfAbsent(t.drinkName, () => []).add(t);
  }

  final items = <ForecastItem>[];
  for (final name in names) {
    final txns = (demand[name] ?? [])
        .where((t) =>
            t.date.isAfter(historyStart) && t.date.isBefore(endInclusive))
        .toList();

    int totalConsumed = 0;
    final weekdayQty = List<int>.filled(7, 0);
    int recentQty = 0;
    int olderQty = 0;
    for (final t in txns) {
      totalConsumed += t.quantity;
      weekdayQty[t.date.weekday - 1] += t.quantity;
      if (t.date.isAfter(midPoint)) {
        recentQty += t.quantity;
      } else {
        olderQty += t.quantity;
      }
    }

    final baseDailyRate = totalConsumed / historyDays;

    // Weekly seasonality (uniform 1/7 fallback when no data).
    final weekdayShare = List<double>.filled(7, 1.0 / 7.0);
    if (totalConsumed > 0) {
      for (int w = 0; w < 7; w++) {
        weekdayShare[w] = weekdayQty[w] / totalConsumed;
      }
    }

    double forecast = 0;
    for (int d = 0; d < horizonDays; d++) {
      final day = now.add(Duration(days: d));
      double daily = baseDailyRate * 7 * weekdayShare[day.weekday - 1];
      for (final e in events) {
        if (e.date.year == day.year &&
            e.date.month == day.month &&
            e.date.day == day.day) {
          daily *= e.multiplier;
        }
      }
      forecast += daily;
    }

    final halfDays = historyDays / 2;
    final recentRate = recentQty / halfDays;
    final olderRate = olderQty / halfDays;
    final trend = olderRate > 0 ? ((recentRate - olderRate) / olderRate) * 100 : 0.0;

    final confidence = (txns.length / 20).clamp(0.1, 1.0).toDouble();

    final stockItems = inventory.where((i) => i.drinkName == name).toList();
    final currentStock = stockItems.fold(0, (s, i) => s + i.quantity);
    final minLevel = stockItems.isEmpty ? 0 : stockItems.first.minStockLevel;

    final rawOrder = forecast + minLevel - currentStock;
    final recommended = rawOrder <= 0 ? 0 : rawOrder.ceil();

    items.add(ForecastItem(
      drinkName: name,
      forecastDemand: forecast,
      currentStock: currentStock,
      minStockLevel: minLevel,
      recommendedOrder: recommended,
      trend: trend,
      confidence: confidence,
    ));
  }

  items.sort((a, b) => b.forecastDemand.compareTo(a.forecastDemand));

  return ForecastResult(horizonDays: horizonDays, items: items, events: events);
}
