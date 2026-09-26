// utils/variance_helper.dart
// Shrinkage / variance: what left the shelf without being sold.
//
// The app already logs every movement (`InventoryTransaction.type` + `reason` +
// `performedBy`), so this is pure computation over data that is already
// captured — nothing here writes anything:
//   * an `out` movement whose reason is NOT a sale is a LOSS (waste, damage,
//     expiry, a stock-take correction, or a reason nobody wrote down);
//   * a sale is valued at the selling price, a loss at cost (what it cost the
//     shop, never the retail price — otherwise the number is inflated).
//
// The point of the report is the question it answers: "who let this leave the
// shelf, and did anybody say why?"

import '../models/inventory_model.dart';

/// One loss: units that left the shelf without a sale behind them.
class VarianceEvent {
  final String drinkId;
  final String drinkName;
  final String reason;
  final String staffName;
  final int units;

  /// Cost per unit (0 when the price was never recorded).
  final double unitCost;
  final DateTime? at;

  const VarianceEvent({
    required this.drinkId,
    required this.drinkName,
    required this.reason,
    this.staffName = '',
    required this.units,
    this.unitCost = 0,
    this.at,
  });

  /// What the shop lost, at cost.
  double get value => units * unitCost;

  /// True when nobody explained why the stock left (a reason that is blank or
  /// not one of the known ones). These are the entries worth asking about.
  bool get isUnexplained =>
      !VarianceHelper.explainedReasons.contains(reason.trim().toLowerCase());

  /// i18n key for this reason.
  String get reasonKey => VarianceHelper.reasonKey(reason);
}

/// Totals for a set of losses.
class VarianceTotals {
  final int units;
  final double value;
  final int events;
  final int unexplainedUnits;
  final double unexplainedValue;
  final int unexplainedEvents;

  const VarianceTotals({
    this.units = 0,
    this.value = 0,
    this.events = 0,
    this.unexplainedUnits = 0,
    this.unexplainedValue = 0,
    this.unexplainedEvents = 0,
  });

  bool get isEmpty => events == 0;
}

class VarianceHelper {
  VarianceHelper._();

  /// Movements that are sales, not losses.
  static const Set<String> saleReasons = {
    'sale',
    'sold',
    'order',
    'customer',
  };

  /// Reasons a manager has actually given. Anything else (including a blank
  /// reason) counts as "unexplained".
  static const Set<String> explainedReasons = {
    'waste',
    'damage',
    'damaged',
    'breakage',
    'expiry',
    'expired',
    'theft',
    'stocktake',
    'count',
    'error',
    'return',
    'returned',
    'transfer',
    'donation',
    'offer',
    'test',
  };

  /// True when this movement is money leaving the shop without a sale.
  static bool isLoss(InventoryTransaction t) =>
      t.isOutgoing && !saleReasons.contains(t.reason.trim().toLowerCase());

  /// True when this movement is a sale.
  static bool isSale(InventoryTransaction t) =>
      t.isOutgoing && saleReasons.contains(t.reason.trim().toLowerCase());

  /// Cost per unit for a movement: the cost recorded with it, otherwise the
  /// drink's current cost (so an old movement is not valued at zero).
  static double costOf(
    InventoryTransaction t, {
    Map<String, double> costByDrinkId = const {},
  }) {
    final recorded = t.purchasePriceAtSale;
    if (recorded != null && recorded > 0) return recorded;
    return costByDrinkId[t.drinkId] ?? 0;
  }

  /// One movement as a loss, or null when it is not a loss.
  static VarianceEvent? fromTransaction(
    InventoryTransaction t, {
    Map<String, double> costByDrinkId = const {},
  }) {
    if (!isLoss(t)) return null;
    return VarianceEvent(
      drinkId: t.drinkId,
      drinkName: t.drinkName,
      reason: t.reason,
      staffName: t.performedBy ?? '',
      units: t.quantity.abs(),
      unitCost: costOf(t, costByDrinkId: costByDrinkId),
      at: t.date,
    );
  }

  /// Every loss in [transactions], newest first. [since] limits the period.
  static List<VarianceEvent> fromTransactions(
    List<InventoryTransaction> transactions, {
    DateTime? since,
    Map<String, double> costByDrinkId = const {},
  }) {
    final events = <VarianceEvent>[];
    for (final t in transactions) {
      if (since != null && t.date.isBefore(since)) continue;
      final event = fromTransaction(t, costByDrinkId: costByDrinkId);
      if (event != null) events.add(event);
    }
    events.sort((a, b) {
      final da = a.at;
      final db = b.at;
      if (da == null && db == null) return 0;
      if (da == null) return 1;
      if (db == null) return -1;
      return db.compareTo(da);
    });
    return events;
  }

  /// Totals for a set of losses, including how much of it nobody explained.
  static VarianceTotals totals(List<VarianceEvent> events) {
    var units = 0;
    var value = 0.0;
    var unexplainedUnits = 0;
    var unexplainedValue = 0.0;
    var unexplainedEvents = 0;

    for (final event in events) {
      units += event.units;
      value += event.value;
      if (event.isUnexplained) {
        unexplainedUnits += event.units;
        unexplainedValue += event.value;
        unexplainedEvents += 1;
      }
    }

    return VarianceTotals(
      units: units,
      value: _round(value),
      events: events.length,
      unexplainedUnits: unexplainedUnits,
      unexplainedValue: _round(unexplainedValue),
      unexplainedEvents: unexplainedEvents,
    );
  }

  /// Loss value per drink name, biggest first.
  static Map<String, double> valueByDrink(List<VarianceEvent> events) {
    final map = <String, double>{};
    for (final event in events) {
      final key = event.drinkName.isEmpty ? event.drinkId : event.drinkName;
      map[key] = (map[key] ?? 0) + event.value;
    }
    return map;
  }

  /// Loss value per staff member ("Unrecorded" when nobody is on the movement).
  static Map<String, double> valueByStaff(
    List<VarianceEvent> events, {
    String unknownLabel = 'unrecorded',
  }) {
    final map = <String, double>{};
    for (final event in events) {
      final key = event.staffName.trim().isEmpty
          ? unknownLabel
          : event.staffName.trim();
      map[key] = (map[key] ?? 0) + event.value;
    }
    return map;
  }

  /// Loss value per reason, biggest first.
  static Map<String, double> valueByReason(List<VarianceEvent> events) {
    final map = <String, double>{};
    for (final event in events) {
      final key = event.reason.trim().isEmpty ? 'unknown' : event.reason.trim();
      map[key] = (map[key] ?? 0) + event.value;
    }
    return map;
  }

  /// A map of values, ordered biggest first (ready for a ranked list).
  static List<MapEntry<String, double>> ranked(
    Map<String, double> values, {
    int limit = 5,
  }) {
    final list = values.entries.toList()
      ..sort((a, b) {
        final byValue = b.value.compareTo(a.value);
        if (byValue != 0) return byValue;
        return a.key.compareTo(b.key);
      });
    return limit <= 0 ? list : list.take(limit).toList();
  }

  /// What was actually sold in the same period (retail value), so the loss can
  /// be read as a share of turnover.
  static double soldValue(List<InventoryTransaction> transactions) {
    var total = 0.0;
    for (final t in transactions) {
      if (!isSale(t)) continue;
      final price = t.sellingPriceAtSale ?? 0;
      total += t.quantity.abs() * price;
    }
    return _round(total);
  }

  /// Loss as a share of what was sold (0..1). Zero sales means no rate to show.
  static double lossRate({
    required double lossValue,
    required double soldValue,
  }) {
    if (soldValue <= 0) return 0;
    return lossValue / soldValue;
  }

  /// The i18n key for a movement reason.
  static String reasonKey(String reason) {
    switch (reason.trim().toLowerCase()) {
      case 'waste':
        return 'varReasonWaste';
      case 'damage':
      case 'damaged':
      case 'breakage':
        return 'varReasonDamage';
      case 'expiry':
      case 'expired':
        return 'varReasonExpiry';
      case 'theft':
        return 'varReasonTheft';
      case 'stocktake':
      case 'count':
        return 'varReasonStocktake';
      case 'return':
      case 'returned':
        return 'varReasonReturn';
      case 'transfer':
        return 'varReasonTransfer';
      case 'error':
        return 'varReasonError';
      default:
        return 'varReasonOther';
    }
  }

  static double _round(double value) => (value * 100).roundToDouble() / 100;
}

