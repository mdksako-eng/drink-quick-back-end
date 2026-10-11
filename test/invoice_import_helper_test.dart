// test/invoice_import_helper_test.dart
// "Edit & Re-invoice" rebuilds a past invoice in the cart. The regression this
// guards: every line must carry the REAL catalogue drink id, or the stock commit
// fails with "not enough stock" while the shelf is full.
import 'package:flutter_test/flutter_test.dart';
import 'package:drinks_calculator_fixed/models/drink_model.dart';
import 'package:drinks_calculator_fixed/models/order_model.dart';
import 'package:drinks_calculator_fixed/utils/invoice_import_helper.dart';

Drink drink({
  String id = 'd1',
  String name = 'Beer',
  double price = 1000.0,
  int stock = 7,
}) =>
    Drink(
      id: id,
      name: name,
      price: price,
      imageUrl: '',
      currentStock: stock,
      minimumLevel: 3,
      purchasePrice: 600.0,
      unit: 'Bottle',
    );

OrderItem item(String name, int qty, [double price = 1000.0]) => OrderItem(
      drinkName: name,
      quantity: qty,
      pricePerUnit: price,
    );

void main() {
  final catalog = [
    drink(),
    drink(id: 'd2', name: 'Water', price: 500.0, stock: 20),
  ];

  group('resolving an invoice line', () {
    test('matches the catalogue drink by name, ignoring case and spaces', () {
      expect(InvoiceImportHelper.findCatalogDrink('  beer ', catalog)?.id, 'd1');
      expect(InvoiceImportHelper.findCatalogDrink('BEER', catalog)?.id, 'd1');
      expect(InvoiceImportHelper.findCatalogDrink('Water', catalog)?.id, 'd2');
    });

    test('an unknown or empty name resolves to nothing', () {
      expect(InvoiceImportHelper.findCatalogDrink('Cola', catalog), isNull);
      expect(InvoiceImportHelper.findCatalogDrink('   ', catalog), isNull);
      expect(InvoiceImportHelper.findCatalogDrink('', catalog), isNull);
    });
  });

  group('rebuilding the cart', () {
    test('one entry per unit, each with the real catalogue id', () {
      final plan = InvoiceImportHelper.plan(
        items: [item('Beer', 2)],
        catalog: catalog,
      );
      expect(plan.canImport, isTrue);
      expect(plan.drinks.length, 2);
      // THE regression: never 'import_<timestamp>_1_Beer'.
      expect(plan.drinks.map((d) => d.id).toSet(), {'d1'});
    });

    test('keeps the catalogue identity and stock, but the price paid', () {
      final plan = InvoiceImportHelper.plan(
        items: [item('Beer', 1, 800.0)], // sold at 800, catalogue now 1000
        catalog: catalog,
      );
      final line = plan.drinks.single;
      expect(line.id, 'd1');
      expect(line.price, 800.0);
      expect(line.currentStock, 7);
      expect(line.minimumLevel, 3);
      expect(line.purchasePrice, 600.0);
      expect(line.unit, 'Bottle');
    });

    test('falls back to the catalogue price when the invoice has none', () {
      final plan = InvoiceImportHelper.plan(
        items: [item('Beer', 1, 0.0)],
        catalog: catalog,
      );
      expect(plan.drinks.single.price, 1000.0);
    });

    test('a missing drink stops the whole import instead of inventing a line', () {
      final plan = InvoiceImportHelper.plan(
        items: [item('Beer', 1), item('Retired IPA', 1)],
        catalog: catalog,
      );
      expect(plan.canImport, isFalse);
      expect(plan.missingDrink, 'Retired IPA');
      expect(plan.drinks, isEmpty);
    });

    test('a mixed invoice keeps every line, in order', () {
      final plan = InvoiceImportHelper.plan(
        items: [item('Beer', 2), item('Water', 1)],
        catalog: catalog,
      );
      expect(
        plan.drinks.map((d) => d.name).toList(),
        ['Beer', 'Beer', 'Water'],
      );
    });

    test('an empty invoice imports nothing', () {
      final plan = InvoiceImportHelper.plan(items: const [], catalog: catalog);
      expect(plan.canImport, isFalse);
      expect(plan.drinks, isEmpty);
    });

    test('a zero or negative quantity still means one unit', () {
      expect(
        InvoiceImportHelper.plan(items: [item('Beer', 0)], catalog: catalog)
            .drinks
            .length,
        1,
      );
      expect(
        InvoiceImportHelper.plan(items: [item('Beer', -3)], catalog: catalog)
            .drinks
            .length,
        1,
      );
    });

    test('an empty catalogue cannot import anything', () {
      final plan = InvoiceImportHelper.plan(
        items: [item('Beer', 1)],
        catalog: const [],
      );
      expect(plan.canImport, isFalse);
      expect(plan.missingDrink, 'Beer');
    });
  });
}
