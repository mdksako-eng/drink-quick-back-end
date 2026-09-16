// test/ai_order_parser_test.dart
// Tests for the AI order parser that powers mic/typed ordering → calculator.
import 'package:flutter_test/flutter_test.dart';

import 'package:drinks_calculator_fixed/models/drink_model.dart';
import 'package:drinks_calculator_fixed/utils/ai_order_parser.dart';

Drink _drink(String id, String name, double price) => Drink(
      id: id,
      name: name,
      price: price,
      category: 'Beer',
      imageUrl: '',
    );

final _inventory = [
  _drink('1', 'Mutzig', 1000),
  _drink('2', 'Coca Cola', 600),
  _drink('3', 'Beer', 800),
  _drink('4', 'Cold Beer', 900),
  _drink('5', 'Malta Guinness', 1200),
];

void main() {
  group('parseOrderLines', () {
    test('parses a single spoken order', () {
      final lines = AIOrderParser.parseOrderLines('order two mutzig');
      expect(lines.length, 1);
      expect(lines.single.name, 'mutzig');
      expect(lines.single.quantity, 2);
    });

    test('parses multiple items in one phrase', () {
      final lines = AIOrderParser.parseOrderLines('order 2 beer and 1 coca cola');
      expect(lines.length, 2);
      expect(lines[0].name, 'beer');
      expect(lines[0].quantity, 2);
      expect(lines[1].name, 'coca cola');
      expect(lines[1].quantity, 1);
    });

    test('understands "a" and word numbers', () {
      final lines = AIOrderParser.parseOrderLines('give me a beer');
      expect(lines.length, 1);
      expect(lines.single.quantity, 1);

      final three = AIOrderParser.parseOrderLines('add three malta guinness please');
      expect(three.single.name, 'malta guinness');
      expect(three.single.quantity, 3);
    });

    test('understands the 3x shorthand and trailing quantities', () {
      expect(AIOrderParser.parseOrderLines('3x mutzig').single.quantity, 3);
      expect(AIOrderParser.parseOrderLines('mutzig 4').single.quantity, 4);
    });

    test('ignores pure commands', () {
      expect(AIOrderParser.parseOrderLines('checkout'), isEmpty);
      expect(AIOrderParser.parseOrderLines('clear order'), isEmpty);
    });

    test('clamps absurd quantities', () {
      expect(AIOrderParser.parseOrderLines('9000 beer').single.quantity, 99);
      expect(AIOrderParser.parseOrderLines('0 beer').single.quantity, 1);
    });

    test('keeps numbers that belong to a drink name', () {
      final inventory = [
        _drink('9', '33 Export', 900),
        _drink('1', 'Mutzig', 1000),
      ];
      final lines =
          AIOrderParser.parseOrderLines('order 33 export', inventory: inventory);
      expect(lines.single.name, '33 export');
      expect(lines.single.quantity, 1);

      final qty = AIOrderParser.parseOrderLines('2 33 export',
          inventory: inventory);
      expect(qty.single.name, '33 export');
      expect(qty.single.quantity, 2);
    });
  });

  group('matchDrink', () {
    test('matches exact and partial names case-insensitively', () {
      expect(AIOrderParser.matchDrink('mutzig', _inventory)!.id, '1');
      expect(AIOrderParser.matchDrink('MUTZI', _inventory)!.id, '1');
      expect(AIOrderParser.matchDrink('coca', _inventory)!.id, '2');
    });

    test('tolerates typos', () {
      expect(AIOrderParser.matchDrink('mutzigg', _inventory)!.id, '1');
      expect(AIOrderParser.matchDrink('malta guinies', _inventory)!.id, '5');
    });

    test('prefers the closest name when several contain the query', () {
      // "cold beer" should win over plain "beer".
      expect(AIOrderParser.matchDrink('cold beer', _inventory)!.id, '4');
    });

    test('returns null when nothing is close enough', () {
      expect(AIOrderParser.matchDrink('whisky', _inventory), isNull);
      expect(AIOrderParser.matchDrink('', _inventory), isNull);
    });
  });

  group('matchLines', () {
    test('resolves parsed lines and merges duplicates', () {
      final lines = AIOrderParser.parseOrderLines('2 beer and 3 beers');
      final matched = AIOrderParser.matchLines(lines, _inventory);
      expect(matched.length, 1);
      expect(matched.single.drink.name, 'Beer');
      expect(matched.single.quantity, 5);
    });

    test('drops unknown drinks but keeps the known ones', () {
      final lines = AIOrderParser.parseOrderLines('2 whisky and 1 mutzig');
      final matched = AIOrderParser.matchLines(lines, _inventory);
      expect(matched.length, 1);
      expect(matched.single.drink.id, '1');
      expect(matched.single.quantity, 1);
    });
  });

  group('extractOrderLines (AI replies)', () {
    test('reads an ORDER_JSON block', () {
      const reply = 'Sure! I added those for you.\n'
          'ORDER_JSON: [{"name":"Beer","qty":2},{"name":"Coca Cola","qty":1}]';
      final lines = AIOrderParser.extractOrderLines(reply);
      expect(lines.length, 2);
      expect(lines[0].name, 'Beer');
      expect(lines[0].quantity, 2);
      expect(lines[1].name, 'Coca Cola');
      expect(lines[1].quantity, 1);
    });

    test('tolerates ```json fences and the item/quantity aliases', () {
      const reply = '```json\n'
          'ORDER_JSON: [{"item":"Mutzig","quantity":3}]\n'
          '```';
      final lines = AIOrderParser.extractOrderLines(reply);
      expect(lines.single.name, 'Mutzig');
      expect(lines.single.quantity, 3);
    });

    test('returns nothing when the reply has no order block', () {
      expect(AIOrderParser.extractOrderLines('We open at 8am.'), isEmpty);
    });

    test('stripOrderBlock hides the machine-readable part from the user', () {
      const reply = 'Added 2 beers.\nORDER_JSON: [{"name":"Beer","qty":2}]';
      final cleaned = AIOrderParser.stripOrderBlock(reply);
      expect(cleaned, 'Added 2 beers.');
      expect(cleaned.contains('ORDER_JSON'), isFalse);
    });
  });
}