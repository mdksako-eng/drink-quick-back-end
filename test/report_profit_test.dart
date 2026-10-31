// test/report_profit_test.dart
// The Reports screen's money maths. These tests exist because the old version priced
// history with today's numbers: see the header of utils/report_profit_helper.dart.
import 'package:flutter_test/flutter_test.dart';

import 'package:drinks_calculator_fixed/utils/report_profit_helper.dart';

ProfitLine line({
  String id = 'd1',
  String name = 'Beer',
  int qty = 1,
  String? category,
  double? soldAt,
  double? costAt,
  double? catalogueSell,
  double? catalogueCost,
}) =>
    ProfitLine(
      drinkId: id,
      drinkName: name,
      quantity: qty,
      category: category,
      sellingPriceAtSale: soldAt,
      purchasePriceAtSale: costAt,
      catalogueSellingPrice: catalogueSell,
      cataloguePurchasePrice: catalogueCost,
    );

void main() {
  group('basis of the figures', () {
    test('prices from the ledger, so a later price change cannot rewrite history',
        () {
      final s = summariseProfit([
        line(
          qty: 10,
          soldAt: 1000,
          costAt: 700,
          // The catalogue has since moved to 1500 / 900 — it must be ignored.
          catalogueSell: 1500,
          catalogueCost: 900,
        ),
      ]);

      expect(s.revenue, 10000);
      expect(s.cost, 7000);
      expect(s.profit, 3000);
      expect(s.marginPercent, closeTo(30, 0.0001));
      expect(s.averageSellingPrice, 1000);
      expect(s.averagePurchasePrice, 700);
      expect(s.unitsSold, 10);
      expect(s.hasCaveat, isFalse);
    });

    test('falls back to the catalogue only when the ledger has no at-sale price',
        () {
      final s = summariseProfit([
        line(qty: 2, soldAt: null, costAt: null, catalogueSell: 500, catalogueCost: 300),
      ]);

      expect(s.revenue, 1000);
      expect(s.cost, 600);
      expect(s.profit, 400);
      expect(s.hasCaveat, isFalse);
    });

    test('a drink that left the catalogue is unvalued, not counted as 0 revenue',
        () {
      final s = summariseProfit([line(qty: 4, name: 'Retired drink')]);

      expect(s.revenue, 0);
      expect(s.unitsSold, 0);
      expect(s.unitsUnvalued, 4);
      expect(s.hasCaveat, isTrue);
    });

    test('an unknown cost is never invented as 0 — the old 100 % margin bug', () {
      final s = summariseProfit([line(qty: 2, soldAt: 500)]);

      // The money that came in still counts...
      expect(s.revenue, 1000);
      expect(s.unitsSold, 2);
      // ...but no cost is assumed, and the caller is told to say so.
      expect(s.cost, 0);
      expect(s.unitsWithoutCost, 2);
      expect(s.unitsCosted, 0);
      expect(s.marginPercent, 100);
      expect(s.hasCaveat, isTrue);
      expect(s.averagePurchasePrice, 0); // no divide-by-zero
    });

    test('a cost of 0 means "no cost on record", not a real zero', () {
      final s = summariseProfit([line(qty: 3, soldAt: 500, costAt: 0)]);

      expect(s.cost, 0);
      expect(s.unitsWithoutCost, 3);
      expect(s.hasCaveat, isTrue);
    });

    test('a selling price of 0 is kept: giving a unit away is a real price', () {
      final s = summariseProfit([line(qty: 1, soldAt: 0, costAt: 400)]);

      expect(s.revenue, 0);
      expect(s.cost, 400);
      expect(s.profit, -400);
      // Nothing was charged, so there is no margin to state — and no NaN either.
      expect(s.marginPercent, 0);
      expect(s.unitsUnvalued, 0);
    });

    test('zero and negative quantities are ignored', () {
      final s = summariseProfit([
        line(qty: 0, soldAt: 500, costAt: 300),
        line(qty: -3, soldAt: 500, costAt: 300),
      ]);

      expect(s.revenue, 0);
      expect(s.unitsSold, 0);
      expect(s.hasCaveat, isFalse);
    });

    test('no sales at all: no NaN, no divide-by-zero', () {
      final s = summariseProfit(const []);

      expect(s.marginPercent, 0);
      expect(s.averageSellingPrice, 0);
      expect(s.averagePurchasePrice, 0);
      expect(s.hasCaveat, isFalse);
      expect(s.topProfitableDrinks, isEmpty);
    });

    test('a loss comes out negative, not clamped', () {
      final s = summariseProfit([line(qty: 5, soldAt: 400, costAt: 500)]);

      expect(s.profit, -500);
      expect(s.marginPercent, closeTo(-25, 0.0001));
      expect(s.averageSellingPrice, 400);
      expect(s.averagePurchasePrice, 500);
    });
  });

  group('breakdowns', () {
    test('by category and top drinks are priced like the totals', () {
      final s = summariseProfit([
        line(id: 'a', name: 'Beer', qty: 10, category: 'Beer', soldAt: 1000, costAt: 700),
        line(id: 'b', name: 'Cola', qty: 5, category: 'Soft', soldAt: 600, costAt: 400),
      ]);

      expect(s.profitByCategory['Beer'], 3000);
      expect(s.profitByCategory['Soft'], 1000);
      expect(s.topProfitableDrinks.first.key, 'Beer');
      expect(s.topProfitableDrinks.first.value, 3000);
    });

    test('lines with no cost on record stay out of the breakdowns', () {
      final s = summariseProfit([
        line(id: 'a', name: 'Beer', qty: 1, category: 'Beer', soldAt: 1000, costAt: 700),
        line(id: 'b', name: 'Mystery', qty: 1, category: 'Other', soldAt: 1000),
      ]);

      expect(s.profitByCategory.keys, ['Beer']);
      expect(s.topProfitableDrinks.map((e) => e.key), ['Beer']);
      expect(s.unitsWithoutCost, 1);
    });

    test('top drinks are sorted descending and capped', () {
      final s = summariseProfit(
        [
          for (var i = 0; i < 8; i++)
            line(id: 'd$i', name: 'Drink $i', qty: 1, soldAt: 100.0 * (i + 1), costAt: 0.1),
        ],
        topDrinks: 3,
      );

      expect(s.topProfitableDrinks, hasLength(3));
      expect(s.topProfitableDrinks.first.key, 'Drink 7');
      expect(
        s.topProfitableDrinks[0].value >= s.topProfitableDrinks[1].value, isTrue,
      );
    });
  });
}
