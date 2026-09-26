// test/variance_helper_test.dart
// The shrinkage detector: what left the shelf without a sale, valued at cost,
// split by drink / staff / reason. Pure functions, no widgets.
import 'package:flutter_test/flutter_test.dart';
import 'package:drinks_calculator_fixed/models/inventory_model.dart';
import 'package:drinks_calculator_fixed/utils/variance_helper.dart';

InventoryTransaction movement({
  String drinkId = 'd1',
  String drinkName = 'Beer',
  int quantity = 1,
  String type = 'out',
  String reason = 'sale',
  String? performedBy,
  double? cost,
  double? price,
  DateTime? date,
}) =>
    InventoryTransaction(
      id: 'txn_$drinkId$quantity$reason',
      drinkId: drinkId,
      drinkName: drinkName,
      quantity: quantity,
      type: type,
      date: date ?? DateTime(2026, 1, 1, 12),
      reason: reason,
      performedBy: performedBy,
      purchasePriceAtSale: cost,
      sellingPriceAtSale: price,
    );

void main() {
  group('what counts as a loss', () {
    test('a sale is not a loss', () {
      final sale = movement(reason: 'sale', price: 1000);
      expect(VarianceHelper.isSale(sale), isTrue);
      expect(VarianceHelper.isLoss(sale), isFalse);
      expect(VarianceHelper.fromTransaction(sale), isNull);
    });

    test('an outgoing movement with any other reason is a loss', () {
      expect(VarianceHelper.isLoss(movement(reason: 'waste')), isTrue);
      expect(VarianceHelper.isLoss(movement(reason: 'stocktake')), isTrue);
      expect(VarianceHelper.isLoss(movement(reason: '')), isTrue);
    });

    test('stock coming IN is never a loss', () {
      expect(
        VarianceHelper.isLoss(movement(type: 'in', reason: 'restock')),
        isFalse,
      );
    });
  });

  group('valuing a loss', () {
    test('at the cost recorded with the movement', () {
      final event = VarianceHelper.fromTransaction(
        movement(quantity: 3, reason: 'waste', cost: 800),
      );
      expect(event, isNotNull);
      expect(event!.units, 3);
      expect(event.unitCost, 800);
      expect(event.value, 2400);
    });

    test('falling back to the drink cost when the movement has none', () {
      final event = VarianceHelper.fromTransaction(
        movement(quantity: 2, reason: 'damage'),
        costByDrinkId: const {'d1': 500},
      );
      expect(event!.unitCost, 500);
      expect(event.value, 1000);
    });

    test('an unknown cost still counts the units', () {
      final event =
          VarianceHelper.fromTransaction(movement(quantity: 4, reason: 'waste'));
      expect(event!.units, 4);
      expect(event.value, 0);
    });

    test('a negative quantity is read as units lost', () {
      final event = VarianceHelper.fromTransaction(
        movement(quantity: -2, reason: 'waste', cost: 100),
      );
      expect(event!.units, 2);
    });
  });

  group('which entries need explaining', () {
    test('a known reason is explained', () {
      expect(
        VarianceHelper.fromTransaction(movement(reason: 'waste'))!.isUnexplained,
        isFalse,
      );
      expect(
        VarianceHelper.fromTransaction(movement(reason: 'damaged'))!
            .isUnexplained,
        isFalse,
      );
    });

    test('a blank or unknown reason is not', () {
      expect(
        VarianceHelper.fromTransaction(movement(reason: ''))!.isUnexplained,
        isTrue,
      );
      expect(
        VarianceHelper.fromTransaction(movement(reason: 'adjustment'))!
            .isUnexplained,
        isTrue,
      );
    });
  });

  group('the period and the order', () {
    final transactions = [
      movement(reason: 'waste', cost: 100, date: DateTime(2026, 1, 1)),
      movement(reason: 'waste', cost: 100, date: DateTime(2026, 3, 1)),
      movement(reason: 'sale', price: 1000, date: DateTime(2026, 3, 2)),
    ];

    test('only losses are returned', () {
      expect(VarianceHelper.fromTransactions(transactions).length, 2);
    });

    test('the newest loss comes first', () {
      final events = VarianceHelper.fromTransactions(transactions);
      expect(events.first.at, DateTime(2026, 3, 1));
    });

    test('a period hides the older losses', () {
      final events = VarianceHelper.fromTransactions(
        transactions,
        since: DateTime(2026, 2, 1),
      );
      expect(events.length, 1);
    });
  });

  group('totals', () {
    test('value, units and how much nobody explained', () {
      final events = VarianceHelper.fromTransactions([
        movement(reason: 'waste', quantity: 2, cost: 1000),
        movement(reason: '', quantity: 1, cost: 1000),
        movement(reason: 'adjustment', quantity: 3, cost: 1000),
      ]);
      final totals = VarianceHelper.totals(events);
      expect(totals.events, 3);
      expect(totals.units, 6);
      expect(totals.value, 6000);
      expect(totals.unexplainedEvents, 2);
      expect(totals.unexplainedUnits, 4);
      expect(totals.unexplainedValue, 4000);
      expect(VarianceHelper.totals([]).isEmpty, isTrue);
    });
  });

  group('grouping and ranking', () {
    final events = VarianceHelper.fromTransactions([
      movement(
        drinkId: 'd1',
        drinkName: 'Beer',
        quantity: 5,
        cost: 1000,
        reason: 'waste',
        performedBy: 'Bih',
      ),
      movement(
        drinkId: 'd2',
        drinkName: 'Fanta',
        quantity: 2,
        cost: 500,
        reason: 'damage',
        performedBy: 'Awa',
      ),
      movement(drinkId: 'd2', drinkName: 'Fanta', quantity: 4, cost: 500, reason: 'waste'),
    ]);

    test('by drink', () {
      final ranked = VarianceHelper.ranked(VarianceHelper.valueByDrink(events));
      expect(ranked.first.key, 'Beer');
      expect(ranked.first.value, 5000);
      expect(ranked[1].key, 'Fanta');
      expect(ranked[1].value, 3000);
    });

    test('by staff, with the unattributed bucket kept separate', () {
      final byStaff = VarianceHelper.valueByStaff(events);
      expect(byStaff['Bih'], 5000);
      expect(byStaff['Awa'], 1000);
      expect(byStaff['unrecorded'], 2000);
      expect(VarianceHelper.ranked(byStaff).first.key, 'Bih');
    });

    test('by reason', () {
      final byReason = VarianceHelper.valueByReason(events);
      expect(byReason['waste'], 7000);
      expect(byReason['damage'], 1000);
    });

    test('the ranking is limited', () {
      expect(VarianceHelper.ranked({'a': 3, 'b': 2, 'c': 1}, limit: 2).length, 2);
      expect(VarianceHelper.ranked({'a': 3, 'b': 2}, limit: 0).length, 2);
    });
  });

  group('loss against turnover', () {
    test('sold value uses the selling price', () {
      final sold = VarianceHelper.soldValue([
        movement(reason: 'sale', quantity: 10, price: 1000),
        movement(reason: 'waste', quantity: 5, cost: 400),
      ]);
      expect(sold, 10000);
    });

    test('the rate is a share of the sales, and 0 without sales', () {
      expect(VarianceHelper.lossRate(lossValue: 500, soldValue: 10000), 0.05);
      expect(VarianceHelper.lossRate(lossValue: 500, soldValue: 0), 0);
    });
  });

  group('reasons and parsing', () {
    test('known reasons map to their own label', () {
      expect(VarianceHelper.reasonKey('waste'), 'varReasonWaste');
      expect(VarianceHelper.reasonKey('Damage'), 'varReasonDamage');
      expect(VarianceHelper.reasonKey('expired'), 'varReasonExpiry');
      expect(VarianceHelper.reasonKey('theft'), 'varReasonTheft');
      expect(VarianceHelper.reasonKey('stocktake'), 'varReasonStocktake');
      expect(VarianceHelper.reasonKey('adjustment'), 'varReasonOther');
      expect(VarianceHelper.reasonKey(''), 'varReasonOther');
    });

    test('a NUMERIC string from Postgres is read as a number', () {
      final parsed = InventoryTransaction.fromJson(const {
        'id': 'txn1',
        'drink_id': 'd1',
        'drink_name': 'Beer',
        'quantity': 2,
        'type': 'out',
        'reason': 'waste',
        'purchase_price_at_sale': '800.00',
        'selling_price_at_sale': '1200.00',
      });
      expect(parsed.purchasePriceAtSale, 800);
      expect(parsed.sellingPriceAtSale, 1200);
    });
  });
}