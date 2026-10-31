// utils/report_profit_helper.dart
//
// The money side of the Reports screen, as pure functions so it can be tested
// without pumping a widget.
//
// WHY THIS EXISTS. The screen used to price a historical sale with TODAY's numbers:
// `drink.price` from the current catalogue and `item.purchasePrice` from the current
// stock row. Two consequences, both wrong:
//   1. editing a price this afternoon silently rewrote last month's report;
//   2. when the drink had left the catalogue (or had no stock row at all) the lookup
//      fell back to a zero object, so the sale contributed 0 revenue AND 0 cost —
//      which the margin then reported as 100 %.
// The inventory ledger already stores the immutable basis: `sellingPriceAtSale` and
// `purchasePriceAtSale` on every sale movement. This helper uses that, falls back to
// the catalogue only for legacy movements written before those columns existed, and
// never invents a cost of 0: units whose cost is unknown are counted and left out of
// the cost, and the caller is expected to show that caveat instead of a flattering
// margin.

/// One sale line, with the catalogue values already resolved by the caller.
class ProfitLine {
  const ProfitLine({
    required this.drinkId,
    required this.drinkName,
    required this.quantity,
    this.category,
    this.sellingPriceAtSale,
    this.purchasePriceAtSale,
    this.catalogueSellingPrice,
    this.cataloguePurchasePrice,
  });

  final String drinkId;
  final String drinkName;
  final int quantity;

  /// Stock category, for the by-category breakdown. Null groups under `''`.
  final String? category;

  /// What was actually charged for this sale. Immutable, from the ledger.
  final double? sellingPriceAtSale;

  /// What the unit cost when it was sold. Immutable, from the ledger.
  final double? purchasePriceAtSale;

  /// Fallbacks for legacy movements that predate the at-sale prices.
  final double? catalogueSellingPrice;
  final double? cataloguePurchasePrice;
}

/// What the Reports screen shows: totals, the margin, the per-unit averages and the
/// two breakdowns, all from one pass over the same lines so the cards always
/// reconcile with each other.
class ProfitSummary {
  const ProfitSummary({
    required this.revenue,
    required this.cost,
    required this.unitsSold,
    required this.unitsWithoutCost,
    required this.unitsUnvalued,
    required this.profitByCategory,
    required this.topProfitableDrinks,
  });

  static const ProfitSummary empty = ProfitSummary(
    revenue: 0,
    cost: 0,
    unitsSold: 0,
    unitsWithoutCost: 0,
    unitsUnvalued: 0,
    profitByCategory: {},
    topProfitableDrinks: [],
  );

  final double revenue;
  final double cost;
  final int unitsSold;

  /// Units with no cost price on record. Excluded from [cost], so [profit] and
  /// [marginPercent] are upper bounds while this is non-zero.
  final int unitsWithoutCost;

  /// Units that could not be valued at all — no at-sale price and the drink has left
  /// the catalogue. Excluded from every figure rather than counted as zero.
  final int unitsUnvalued;

  /// Profit per category, over the fully-valued lines only.
  final Map<String, double> profitByCategory;

  /// Best lines by profit, descending.
  final List<MapEntry<String, double>> topProfitableDrinks;

  double get profit => revenue - cost;

  /// Margin on revenue, in percent. 0 when nothing was sold (never NaN).
  double get marginPercent => revenue == 0 ? 0 : (profit / revenue) * 100;

  /// Average price per unit SOLD in the period — what the shop actually charged.
  double get averageSellingPrice => unitsSold == 0 ? 0 : revenue / unitsSold;

  /// Units whose cost is known; the denominator of [averagePurchasePrice].
  int get unitsCosted => unitsSold - unitsWithoutCost;

  /// Average cost per unit sold, over the units whose cost is on record.
  double get averagePurchasePrice => unitsCosted == 0 ? 0 : cost / unitsCosted;

  /// True when the figures need a caveat on screen.
  bool get hasCaveat => unitsWithoutCost > 0 || unitsUnvalued > 0;
}

/// Prices [lines] and totals them. Pass sale movements only — the caller filters.
ProfitSummary summariseProfit(Iterable<ProfitLine> lines, {int topDrinks = 5}) {
  var revenue = 0.0;
  var cost = 0.0;
  var unitsSold = 0;
  var unitsWithoutCost = 0;
  var unitsUnvalued = 0;
  final byCategory = <String, double>{};
  final byDrink = <String, double>{};

  for (final line in lines) {
    final qty = line.quantity;
    if (qty <= 0) continue;

    final sell = line.sellingPriceAtSale ?? line.catalogueSellingPrice;
    if (sell == null) {
      // No price anywhere: the drink has left the catalogue and the movement predates
      // the at-sale prices. Counting it as 0 revenue would understate the period, so
      // it is reported as unvalued instead.
      unitsUnvalued += qty;
      continue;
    }

    // Revenue is real money that came in, so it always counts.
    final lineRevenue = sell * qty;
    revenue += lineRevenue;
    unitsSold += qty;

    final buy = _positiveOrNull(line.purchasePriceAtSale) ??
        _positiveOrNull(line.cataloguePurchasePrice);
    if (buy == null) {
      // Never invent a cost of 0: that is the bug that made a sale look like 100 %
      // margin. The units are counted instead and the caller shows the caveat.
      unitsWithoutCost += qty;
      continue;
    }

    final lineCost = buy * qty;
    cost += lineCost;
    final lineProfit = lineRevenue - lineCost;
    final category = line.category ?? '';
    byCategory[category] = (byCategory[category] ?? 0) + lineProfit;
    byDrink[line.drinkName] = (byDrink[line.drinkName] ?? 0) + lineProfit;
  }

  final sorted = byDrink.entries.toList()
    ..sort((a, b) => b.value.compareTo(a.value));

  return ProfitSummary(
    revenue: revenue,
    cost: cost,
    unitsSold: unitsSold,
    unitsWithoutCost: unitsWithoutCost,
    unitsUnvalued: unitsUnvalued,
    profitByCategory: byCategory,
    topProfitableDrinks: sorted.take(topDrinks).toList(),
  );
}

/// A cost of 0 (or less) is read as "no cost on record". A stock row can exist with a
/// purchase price that was never filled in, and treating that as a real 0 is the same
/// 100 %-margin lie in another disguise. A *selling* price of 0 is left alone: giving
/// a unit away is a real thing a shop does.
double? _positiveOrNull(double? value) =>
    (value == null || value <= 0) ? null : value;
