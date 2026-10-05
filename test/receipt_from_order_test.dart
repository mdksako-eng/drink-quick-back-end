// test/receipt_from_order_test.dart
// Reprinting a past order: mapping the stored order back to the receipt screen.
import 'package:flutter_test/flutter_test.dart';
import 'package:drinks_calculator_fixed/models/order_model.dart';
import 'package:drinks_calculator_fixed/utils/receipt_from_order.dart';

PurchaseHistory order({
  List<OrderItem>? items,
  String customerName = '',
  double total = 0,
  double paid = 0,
}) =>
    PurchaseHistory(
      id: 'order_1',
      date: DateTime(2026, 9, 27, 14, 30),
      items: items ??
          [
            OrderItem(drinkName: 'Beer', quantity: 3, pricePerUnit: 1000),
            OrderItem(drinkName: 'Water', quantity: 1, pricePerUnit: 500),
          ],
      totalAmount: total,
      amountPaid: paid,
      customerName: customerName,
    );

void main() {
  group('drinksFor', () {
    test('expands each line into one entry per sold unit', () {
      final drinks = ReceiptFromOrder.drinksFor(order());
      expect(drinks.length, 4); // 3 beers + 1 water
      expect(drinks.where((d) => d.name == 'Beer').length, 3);
      expect(drinks.where((d) => d.name == 'Water').length, 1);
    });

    test('keeps the unit price of each line', () {
      final drinks = ReceiptFromOrder.drinksFor(order());
      expect(drinks.firstWhere((d) => d.name == 'Beer').price, 1000);
      expect(drinks.firstWhere((d) => d.name == 'Water').price, 500);
    });

    test('gives every entry a unique id', () {
      final ids = ReceiptFromOrder.drinksFor(order()).map((d) => d.id).toSet();
      expect(ids.length, 4);
    });

    test('a missing quantity counts as one unit instead of vanishing', () {
      final drinks = ReceiptFromOrder.drinksFor(order(items: [
        OrderItem(drinkName: 'Fanta', quantity: 0, pricePerUnit: 600),
      ]));
      expect(drinks.length, 1);
      expect(drinks.first.name, 'Fanta');
    });

    test('an order with no items yields no drinks (no crash)', () {
      expect(ReceiptFromOrder.drinksFor(order(items: [])), isEmpty);
    });
  });

  group('customerLabel', () {
    test('uses the recorded name', () {
      expect(
        ReceiptFromOrder.customerLabel(
            order(customerName: 'Bih Marie'), 'Walk-in'),
        'Bih Marie',
      );
    });

    test('falls back for older orders with no name', () {
      expect(ReceiptFromOrder.customerLabel(order(), 'Walk-in'), 'Walk-in');
      expect(
        ReceiptFromOrder.customerLabel(order(customerName: '   '), 'Passager'),
        'Passager',
      );
    });
  });

  group('hasItems', () {
    test('true when there is something to print', () {
      expect(ReceiptFromOrder.hasItems(order()), isTrue);
    });

    test('false when the stored order has no lines', () {
      expect(ReceiptFromOrder.hasItems(order(items: [])), isFalse);
    });
  });

  group('unitCount', () {
    test('counts units, not lines', () {
      expect(ReceiptFromOrder.unitCount(order()), 4);
    });

    test('counts a broken quantity as one', () {
      expect(
        ReceiptFromOrder.unitCount(order(items: [
          OrderItem(drinkName: 'Fanta', quantity: 0, pricePerUnit: 600),
          OrderItem(drinkName: 'Beer', quantity: 2, pricePerUnit: 1000),
        ])),
        3,
      );
    });

    test('zero for an empty order', () {
      expect(ReceiptFromOrder.unitCount(order(items: [])), 0);
    });
  });
}
