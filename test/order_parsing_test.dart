// test/order_parsing_test.dart
// Regression tests for Order.fromJson against Postgres NUMERIC columns.
//
// orders.tab_amount is NUMERIC(12,2) and node-postgres returns NUMERIC/DECIMAL
// as a *string* ("0.00") to avoid losing precision, while integer/double columns
// arrive as numbers. The parser called `.toDouble()` on it, which threw
// NoSuchMethodError inside the per-row loop in OrderProvider.loadOrdersFromSupabase
// — so every order was skipped and the app logged "Found 128 orders in Supabase"
// followed by "Loaded 0 orders". Same class of bug as inventory.purchase_price
// and forecast_events.multiplier.
import 'package:flutter_test/flutter_test.dart';

import 'package:drinks_calculator_fixed/providers/order_provider.dart';
import 'package:drinks_calculator_fixed/utils/json_num.dart';

/// A row exactly as GET /orders returned it in the failing run: the numeric
/// money columns that are INTEGER/DECIMAL come through as numbers, tab_amount
/// (NUMERIC) comes through as the string "0.00".
Map<String, dynamic> _rowFromBackend() => {
      'id': 1781638069611,
      'items': [
        {
          'id': 1781041948076,
          'name': 'malta',
          'price': 5666,
          'category': 'Beer',
          'image_url': '',
          'created_at': null,
          'user_id': null,
          'currentStock': 0,
          'minimumLevel': 5,
          'unit': 'Bottle',
          'purchasePrice': 0,
        }
      ],
      'totalAmount': 5666,
      'amountPaid': 6000,
      'balance': 334,
      'tabAmount': '0.00',
      'customerId': null,
      'receiptNumber': 'REC-1781638069611',
      'date': '2026-06-16T20:27:49.611Z',
      'isActive': true,
      'customerName': 'maxwell',
      'staffName': 'onean',
    };

void main() {
  group('Order.fromJson tolerates NUMERIC columns arriving as strings', () {
    test('parses the row that used to throw on tab_amount "0.00"', () {
      final order = Order.fromJson(_rowFromBackend());

      expect(order.tabAmount, 0);
      expect(order.totalAmount, 5666);
      expect(order.amountPaid, 6000);
      expect(order.balance, 334);
      expect(order.receiptNumber, 'REC-1781638069611');
      expect(order.customerName, 'maxwell');
      expect(order.staffName, 'onean');
      expect(order.isActive, isTrue);
      expect(order.items.single.name, 'malta');
      expect(order.items.single.price, 5666);
    });

    test('reads a real tab left on a customer account', () {
      final order = Order.fromJson({
        ..._rowFromBackend(),
        'amountPaid': '1500.00',
        'tabAmount': '4166.00',
        'customerId': 42,
      });

      expect(order.tabAmount, 4166);
      expect(order.amountPaid, 1500);
      expect(order.customerId, 42);
    });

    test('reads every money field when all four come back as strings', () {
      final order = Order.fromJson({
        ..._rowFromBackend(),
        'total_amount': '5666.00',
        'amount_paid': '6000.00',
        'balance': '334.00',
        'tab_amount': '0.00',
      });

      expect(order.totalAmount, 5666);
      expect(order.amountPaid, 6000);
      expect(order.balance, 334);
      expect(order.tabAmount, 0);
    });

    test('a missing money field is zero, not a crash', () {
      final order = Order.fromJson({
        'id': '1',
        'items': [],
        'receipt_number': 'REC-1',
        'date': '2026-06-16T20:27:49.611Z',
      });

      expect(order.totalAmount, 0);
      expect(order.amountPaid, 0);
      expect(order.balance, 0);
      expect(order.tabAmount, 0);
    });
  });

  group('asDouble', () {
    test('accepts numbers and numeric strings', () {
      expect(asDouble(12), 12);
      expect(asDouble(12.5), 12.5);
      expect(asDouble('12.50'), 12.5);
      expect(asDouble(' 12.50 '), 12.5);
      expect(asDouble('0.00'), 0);
      expect(asDouble('-3.25'), -3.25);
    });

    test('returns null for null, empty and unreadable values', () {
      expect(asDouble(null), isNull);
      expect(asDouble(''), isNull);
      expect(asDouble('   '), isNull);
      expect(asDouble('abc'), isNull);
      expect(asDouble(true), isNull);
    });
  });
}
