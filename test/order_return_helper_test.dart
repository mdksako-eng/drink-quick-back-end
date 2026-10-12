// test/order_return_helper_test.dart
// "Return 1 of 2" — the dialog draws the server's numbers and asks for exactly
// what can come back. The regression this guards: asking for more than is left
// (or for a drink the invoice never carried) makes the backend refuse the WHOLE
// return, so the same unit stays counted twice.
import 'package:flutter_test/flutter_test.dart';
import 'package:drinks_calculator_fixed/utils/order_return_helper.dart';

ReturnableLine line({
  String id = 'd1',
  String name = 'Beer',
  int sold = 2,
  int returned = 0,
  double price = 1000.0,
}) =>
    ReturnableLine(
      drinkId: id,
      drinkName: name,
      sold: sold,
      returned: returned,
      unitPrice: price,
    );

Map<String, dynamic> apiLine(
  Map<String, dynamic> over, [
  Map<String, dynamic> extra = const {},
]) =>
    {
      'drinkId': 'd1',
      'drinkName': 'Beer',
      'sold': 2,
      'returned': 0,
      'unitPrice': 1000,
      ...over,
      ...extra,
    };

void main() {
  group('reading the endpoint', () {
    test('maps the lines the dialog needs', () {
      final lines = OrderReturnHelper.linesFromApi({
        'lines': [apiLine({'returned': 1})],
      });
      expect(lines, hasLength(1));
      expect(lines.single.drinkId, 'd1');
      expect(lines.single.sold, 2);
      expect(lines.single.returned, 1);
      expect(lines.single.remaining, 1);
      expect(lines.single.unitPrice, 1000.0);
    });

    test('accepts the snake_case form and a missing id', () {
      final lines = OrderReturnHelper.linesFromApi({
        'lines': [
          {'drink_id': 'd2', 'drink_name': 'Water', 'sold': 1, 'returned': 0, 'unit_price': 500},
          {'drink_name': 'Cola', 'sold': 3},
        ],
      });
      expect(lines.map((l) => l.drinkId), ['d2', '']);
      expect(lines[1].drinkName, 'Cola');
      expect(lines[1].remaining, 3);
      expect(lines[1].unitPrice, 0.0);
    });

    test('drops junk and a payload without lines', () {
      expect(OrderReturnHelper.linesFromApi({}), isEmpty);
      expect(OrderReturnHelper.linesFromApi({'lines': 'nope'}), isEmpty);
      expect(
        OrderReturnHelper.linesFromApi({
          'lines': [null, 'x', <String, dynamic>{}, apiLine({})],
        }).map((l) => l.drinkName),
        ['Beer'],
      );
    });

    test('clamps an over-returned or nonsensical line instead of trusting it', () {
      final lines = OrderReturnHelper.linesFromApi({
        'lines': [
          apiLine({'returned': 5}), // more back than sold
          apiLine({'drinkId': 'd2', 'sold': -3, 'returned': 0}),
        ],
      });
      expect(lines[0].remaining, 0);
      expect(lines[0].canReturn, isFalse);
      expect(lines[1].sold, 0);
      expect(lines[1].remaining, 0);
    });
  });

  group('building the request', () {
    test('sends only what is chosen, once per drink', () {
      final lines = [line(), line(id: 'd2', name: 'Water', price: 500)];
      final items = OrderReturnHelper.requestItems(lines, {'d2': 1});
      expect(items, [
        {'drink_id': 'd2', 'drink_name': 'Water', 'quantity': 1},
      ]);
    });

    test('zero and negative choices are left out', () {
      final lines = [line()];
      expect(OrderReturnHelper.requestItems(lines, {'d1': 0}), isEmpty);
      expect(OrderReturnHelper.requestItems(lines, {'d1': -2}), isEmpty);
      expect(OrderReturnHelper.requestItems(lines, const {}), isEmpty);
    });

    test('never asks for more than remains, and never for a returned line', () {
      final lines = [line(returned: 1), line(id: 'd2', name: 'Water', sold: 1, returned: 1)];
      final items = OrderReturnHelper.requestItems(lines, {'d1': 5, 'd2': 1});
      expect(items, [
        {'drink_id': 'd1', 'drink_name': 'Beer', 'quantity': 1},
      ]);
    });

    test('one of two comes back with one action', () {
      final lines = [line()];
      final chosen = {'d1': 1};
      expect(OrderReturnHelper.totalUnits(lines, chosen), 1);
      expect(OrderReturnHelper.totalAmount(lines, chosen), 1000.0);
      expect(OrderReturnHelper.anyReturnable(lines), isTrue);
    });

    test('the refund follows the price paid, not a rounded sum', () {
      final lines = [line(sold: 3, price: 333.33)];
      expect(OrderReturnHelper.totalAmount(lines, {'d1': 3}), closeTo(999.99, 0.001));
    });

    test('nothing is left once every line came back', () {
      final lines = [line(returned: 2)];
      expect(OrderReturnHelper.anyReturnable(lines), isFalse);
      expect(OrderReturnHelper.requestItems(lines, {'d1': 1}), isEmpty);
      expect(OrderReturnHelper.totalAmount(lines, {'d1': 1}), 0.0);
    });
  });

  group('a whole sale comes back', () {
    // This app is not only bars: a company can sell a whole crate sale of 24
    // units at once, and give the lot back. Selecting everything must be one
    // action, not twenty-four taps.
    final bulk = [
      line(sold: 24, price: 500),
      line(id: 'd2', name: 'Water', sold: 6, price: 300),
      line(id: 'd3', name: 'Juice', sold: 1, returned: 1, price: 700),
    ];

    test('all left takes every line that still has something to give', () {
      expect(OrderReturnHelper.allRemaining(bulk), {'d1': 24, 'd2': 6});
    });

    test('the whole sale totals in units and in money', () {
      final all = OrderReturnHelper.allRemaining(bulk);
      expect(OrderReturnHelper.totalUnits(bulk, all), 30);
      expect(OrderReturnHelper.totalAmount(bulk, all), 24 * 500.0 + 6 * 300.0);
      expect(OrderReturnHelper.requestItems(bulk, all), [
        {'drink_id': 'd1', 'drink_name': 'Beer', 'quantity': 24},
        {'drink_id': 'd2', 'drink_name': 'Water', 'quantity': 6},
      ]);
    });

    test('a typed quantity larger than what is left is capped, not refused', () {
      final lines = [line(sold: 24)];
      expect(OrderReturnHelper.requestItems(lines, {'d1': 99}), [
        {'drink_id': 'd1', 'drink_name': 'Beer', 'quantity': 24},
      ]);
      expect(OrderReturnHelper.totalUnits(lines, {'d1': 99}), 24);
    });

    test('an empty or fully returned invoice selects nothing', () {
      expect(OrderReturnHelper.allRemaining(const []), isEmpty);
      expect(OrderReturnHelper.allRemaining([line(returned: 2)]), isEmpty);
    });
  });
}
