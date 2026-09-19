// test/drink_batch_dates_test.dart
// Guards the production/expiry date fix: the payloads posted to
// /api/data/drinks must carry the batch dates (the server whitelists them) and
// a server row must round-trip back into Drink with its dates intact.
//
// Before the fix the payload builders dropped unit_kind / production_date /
// expiry_date entirely and the read mapping dropped them again, so the dates
// were silently lost and always came back null.
import 'package:flutter_test/flutter_test.dart';

import 'package:drinks_calculator_fixed/models/drink_model.dart';
import 'package:drinks_calculator_fixed/services/supabase_service.dart';

void main() {
  group('SupabaseService.dateOnly', () {
    test('formats a DateTime as a Postgres DATE', () {
      expect(SupabaseService.dateOnly(DateTime(2026, 3, 7, 15, 30)), '2026-03-07');
    });

    test('accepts an ISO timestamp string', () {
      expect(SupabaseService.dateOnly('2026-12-31T23:59:00.000Z'), '2026-12-31');
    });

    test('accepts an already plain date', () {
      expect(SupabaseService.dateOnly('2026-01-05'), '2026-01-05');
    });

    test('pads single digit months and days', () {
      expect(SupabaseService.dateOnly(DateTime(2026, 1, 2)), '2026-01-02');
    });

    test('returns null for null, empty and whitespace', () {
      expect(SupabaseService.dateOnly(null), isNull);
      expect(SupabaseService.dateOnly(''), isNull);
      expect(SupabaseService.dateOnly('   '), isNull);
    });
  });

  group('insert payload (POST /api/data/drinks)', () {
    final json = Drink(
      id: 'd1',
      name: 'Beer',
      price: 1000,
      imageUrl: 'https://img/beer.png',
      purchasePrice: 600,
      unitsPerPack: 12,
      unitKind: 'volume',
      productionDate: DateTime(2026, 2, 1),
      expiryDate: DateTime(2026, 8, 1),
    ).toJson();

    test('writes both batch dates in yyyy-MM-dd', () {
      final payload = SupabaseService.buildDrinkInsertPayload(
        json,
        companyId: 7,
        userId: 3,
        now: DateTime(2026, 2, 1, 10),
      );
      expect(payload['production_date'], '2026-02-01');
      expect(payload['expiry_date'], '2026-08-01');
    });

    test('keeps the unit kind and company scope', () {
      final payload = SupabaseService.buildDrinkInsertPayload(
        json,
        companyId: 7,
        userId: 3,
      );
      expect(payload['unit_kind'], 'volume');
      expect(payload['company_id'], 7);
      expect(payload['created_by'], 3);
    });

    test('keeps the image url (local toJson keys it image_url)', () {
      final payload = SupabaseService.buildDrinkInsertPayload(
        json,
        companyId: 7,
        userId: 3,
      );
      expect(payload['image_url'], 'https://img/beer.png');
    });

    test('never sends current_stock (inventory owns the quantity)', () {
      final payload = SupabaseService.buildDrinkInsertPayload(
        json,
        companyId: 7,
        userId: 3,
      );
      expect(payload.containsKey('current_stock'), isFalse);
    });
  });

  group('update payload (PATCH /api/data/drinks/:id)', () {
    test('carries the batch dates and unit kind when set', () {
      final payload = SupabaseService.buildDrinkUpdatePayload(
        Drink(
          id: 'd1',
          name: 'Beer',
          price: 10,
          imageUrl: 'https://img/beer.png',
          unitKind: 'mass',
          productionDate: DateTime(2026, 4, 9),
          expiryDate: DateTime(2026, 10, 9),
        ).toJson(),
      );
      expect(payload['production_date'], '2026-04-09');
      expect(payload['expiry_date'], '2026-10-09');
      expect(payload['unit_kind'], 'mass');
    });

    test('sends explicit nulls so a batch date can be cleared', () {
      final payload = SupabaseService.buildDrinkUpdatePayload(
        Drink(id: 'd1', name: 'Beer', price: 10, imageUrl: 'i').toJson(),
      );
      expect(payload.containsKey('production_date'), isTrue);
      expect(payload['production_date'], isNull);
      expect(payload['expiry_date'], isNull);
    });

    test('never wipes image_url when the local key is camelCase', () {
      final payload = SupabaseService.buildDrinkUpdatePayload({
        'name': 'Beer',
        'price': 10,
        'imageUrl': 'https://img/beer.png',
      });
      expect(payload['image_url'], 'https://img/beer.png');
    });
  });

  group('server row mapping', () {
    test('round-trips the batch dates into Drink', () {
      final drink = Drink.fromJson(SupabaseService.mapDrinkRow({
        'id': 12,
        'name': 'Amstel',
        'price': 1200,
        'category': 'Beer',
        'image_url': 'https://img/amstel.png',
        'current_stock': 24,
        'minimum_level': 6,
        'purchase_price': 800,
        'unit': 'Bottle',
        'barcode': 'ABC123',
        'units_per_pack': 12,
        'unit_kind': 'volume',
        'production_date': '2026-05-01',
        'expiry_date': '2026-11-01',
      }));
      expect(drink.productionDate, DateTime.parse('2026-05-01'));
      expect(drink.expiryDate, DateTime.parse('2026-11-01'));
      expect(drink.unitKind, 'volume');
      expect(drink.imageUrl, 'https://img/amstel.png');
      expect(drink.currentStock, 24);
      expect(drink.unitsPerPack, 12);
      expect(drink.barcode, 'ABC123');
    });

    test('tolerates missing batch columns', () {
      final drink = Drink.fromJson(SupabaseService.mapDrinkRow({
        'id': 1,
        'name': 'Water',
        'price': 100,
        'image_url': null,
      }));
      expect(drink.productionDate, isNull);
      expect(drink.expiryDate, isNull);
      expect(drink.unitKind, 'count');
      expect(drink.minimumLevel, 5);
    });
  });

  group('Drink batch warnings', () {
    Drink withExpiry(DateTime? expiry) => Drink(
          id: 'd',
          name: 'n',
          price: 1,
          imageUrl: 'i',
          expiryDate: expiry,
        );

    test('flags a batch expiring within 30 days as soon', () {
      final soon = withExpiry(DateTime.now().add(const Duration(days: 5)));
      expect(soon.isExpiringSoon, isTrue);
      expect(soon.isExpired, isFalse);
    });

    test('flags a past expiry date as expired', () {
      final gone = withExpiry(DateTime.now().subtract(const Duration(days: 2)));
      expect(gone.isExpired, isTrue);
      expect(gone.isExpiringSoon, isFalse);
    });

    test('without an expiry date neither flag is set', () {
      final none = withExpiry(null);
      expect(none.isExpired, isFalse);
      expect(none.isExpiringSoon, isFalse);
    });
  });
}
