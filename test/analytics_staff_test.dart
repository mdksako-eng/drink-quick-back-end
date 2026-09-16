// test/analytics_staff_test.dart
// Regression tests for the manager dashboard "Sales by Staff" section
// (lib/utils/analytics_helper.dart + the Order <-> backend staff_name mapping).
import 'package:flutter_test/flutter_test.dart';

import 'package:drinks_calculator_fixed/models/drink_model.dart';
import 'package:drinks_calculator_fixed/providers/order_provider.dart';
import 'package:drinks_calculator_fixed/utils/analytics_helper.dart';

Drink _drink(String name, double price) => Drink(
      id: name.toLowerCase(),
      name: name,
      price: price,
      category: 'Beer',
      imageUrl: '',
    );

Order _order({
  required String id,
  required DateTime date,
  required List<Drink> items,
  String staffName = '',
  bool isActive = true,
}) {
  final total = items.fold<double>(0, (sum, d) => sum + d.price);
  return Order(
    id: id,
    items: items,
    totalAmount: total,
    amountPaid: total,
    balance: 0,
    receiptNumber: 'REC-$id',
    date: date,
    isActive: isActive,
    staffName: staffName,
  );
}

void main() {
  final now = DateTime.now();
  final start = now.subtract(const Duration(days: 7));

  group('computeAnalytics — sales by staff', () {
    test('groups revenue, orders and items per staff member (highest first)',
        () {
      final orders = [
        _order(
          id: '1',
          date: now,
          staffName: 'Alice',
          items: [_drink('Beer', 2), _drink('Soda', 3)],
        ),
        _order(id: '2', date: now, staffName: 'Bob', items: [_drink('Beer', 2)]),
        _order(id: '3', date: now, staffName: 'Alice', items: [_drink('Wine', 10)]),
      ];

      final snapshot =
          computeAnalytics(orders: orders, startDate: start, endDate: now);

      expect(snapshot.staffSales.length, 2);

      final alice = snapshot.staffSales.first;
      expect(alice.name, 'Alice');
      expect(alice.revenue, 15);
      expect(alice.orders, 2);
      expect(alice.itemsSold, 3);

      final bob = snapshot.staffSales.last;
      expect(bob.name, 'Bob');
      expect(bob.revenue, 2);
      expect(bob.orders, 1);
      expect(bob.itemsSold, 1);
    });

    test('orders without a staff name are not attributed to anyone', () {
      final orders = [
        _order(id: '1', date: now, items: [_drink('Beer', 5)]),
        _order(id: '2', date: now, staffName: 'Bob', items: [_drink('Beer', 2)]),
      ];

      final snapshot =
          computeAnalytics(orders: orders, startDate: start, endDate: now);

      expect(snapshot.staffSales.length, 1);
      expect(snapshot.staffSales.single.name, 'Bob');
      // The unattributed order still counts towards the KPI totals.
      expect(snapshot.totalOrders, 2);
      expect(snapshot.totalRevenue, 7);
    });

    test('inactive and out-of-range orders are excluded from staff totals', () {
      final orders = [
        _order(id: '1', date: now, staffName: 'Alice', items: [_drink('Beer', 2)]),
        _order(
          id: '2',
          date: now,
          staffName: 'Bob',
          items: [_drink('Beer', 9)],
          isActive: false,
        ),
        _order(
          id: '3',
          date: now.subtract(const Duration(days: 40)),
          staffName: 'Carol',
          items: [_drink('Beer', 7)],
        ),
      ];

      final snapshot =
          computeAnalytics(orders: orders, startDate: start, endDate: now);

      expect(snapshot.staffSales.length, 1);
      expect(snapshot.staffSales.single.name, 'Alice');
      expect(snapshot.staffSales.single.revenue, 2);
    });

    test('no staff names → empty list (card shows its empty state)', () {
      final orders = [_order(id: '1', date: now, items: [_drink('Beer', 5)])];

      final snapshot =
          computeAnalytics(orders: orders, startDate: start, endDate: now);

      expect(snapshot.staffSales, isEmpty);
      expect(snapshot.totalOrders, 1);
    });
  });

  group('Order staff_name mapping (backend <-> app)', () {
    test('fromJson reads the backend staff_name column returned by GET /orders',
        () {
      final order = Order.fromJson({
        'id': '1',
        'items': [],
        'total_amount': 10,
        'amount_paid': 10,
        'balance': 0,
        'receipt_number': 'REC-1',
        'date': now.toIso8601String(),
        'is_active': true,
        'customer_name': 'Jo',
        'staff_name': 'Alice',
      });

      expect(order.staffName, 'Alice');
    });

    test('fromJson falls back to the camelCase staffName key', () {
      final order = Order.fromJson({
        'id': '2',
        'items': [],
        'totalAmount': 5,
        'amountPaid': 5,
        'balance': 0,
        'receiptNumber': 'REC-2',
        'date': now.toIso8601String(),
        'staffName': 'Bob',
      });

      expect(order.staffName, 'Bob');
    });

    test('fromJson defaults to an empty name when the field is missing', () {
      final order = Order.fromJson({
        'id': '3',
        'items': [],
        'total_amount': 1,
        'amount_paid': 1,
        'balance': 0,
        'receipt_number': 'REC-3',
        'date': now.toIso8601String(),
      });

      expect(order.staffName, '');
    });

    test('toJson exposes staff_name so SaveOrder persists the staff member', () {
      final order = _order(
        id: '4',
        date: now,
        items: [_drink('Beer', 2)],
        staffName: 'Carol',
      );

      expect(order.toJson()['staff_name'], 'Carol');
      expect(order.toJson()['staffName'], 'Carol');
    });
  });
}
