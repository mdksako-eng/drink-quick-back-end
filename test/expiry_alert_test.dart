// test/expiry_alert_test.dart
// Guards the "30 days before expiry" alert and its join with the demand
// forecast: the alert must fire inside the window, name the batch, and carry the
// expected demand / suggested order so the stock can be pushed before it spoils.
import 'package:flutter_test/flutter_test.dart';

import 'package:drinks_calculator_fixed/models/drink_model.dart';
import 'package:drinks_calculator_fixed/models/forecast_model.dart';
import 'package:drinks_calculator_fixed/utils/expiry_alert_helper.dart';

Drink drink({
  required String name,
  DateTime? expiry,
  int stock = 10,
  String id = 'd1',
}) =>
    Drink(
      id: id,
      name: name,
      price: 1000,
      imageUrl: 'i',
      currentStock: stock,
      expiryDate: expiry,
    );

String t(String key) => const {
      'expiryAlreadyExpired': 'already expired',
      'expiryDaysLeft': 'day(s) left',
      'expiryExpectedDemand': 'expected demand',
      'expirySuggestedOrder': 'suggested order',
    }[key] ??
    key;

ForecastResult forecastWith(List<ForecastItem> items) =>
    ForecastResult(horizonDays: 7, items: items, events: const []);

ForecastItem item(String name, {double demand = 0, int order = 0}) =>
    ForecastItem(
      drinkName: name,
      forecastDemand: demand,
      currentStock: 10,
      minStockLevel: 5,
      recommendedOrder: order,
      trend: 0,
      confidence: 0.5,
    );

void main() {
  final today = DateTime.now();

  group('computeExpiryAlerts', () {
    test('ignores drinks without an expiry date', () {
      expect(computeExpiryAlerts(drinks: [drink(name: 'Beer')]), isEmpty);
    });

    test('ignores drinks that expire far in the future', () {
      final alerts = computeExpiryAlerts(drinks: [
        drink(name: 'Beer', expiry: today.add(const Duration(days: 120))),
      ]);
      expect(alerts, isEmpty);
    });

    test('flags a batch expiring inside the 30-day window', () {
      final alerts = computeExpiryAlerts(drinks: [
        drink(name: 'Beer', expiry: today.add(const Duration(days: 4))),
      ]);
      expect(alerts, hasLength(1));
      expect(alerts.first.drinkName, 'Beer');
      expect(alerts.first.isExpired, isFalse);
      expect(alerts.first.daysLeft, inInclusiveRange(3, 4));
    });

    test('the 30-day boundary is inclusive', () {
      final at = computeExpiryAlerts(drinks: [
        drink(name: 'Edge', expiry: today.add(const Duration(days: 30))),
      ]);
      expect(at, hasLength(1));

      final beyond = computeExpiryAlerts(drinks: [
        drink(name: 'Beyond', expiry: today.add(const Duration(days: 31))),
      ]);
      expect(beyond, isEmpty);
    });

    test('flags an already expired batch and reports negative days', () {
      final alerts = computeExpiryAlerts(drinks: [
        drink(name: 'Old', expiry: today.subtract(const Duration(days: 3))),
      ]);
      expect(alerts, hasLength(1));
      expect(alerts.first.isExpired, isTrue);
      expect(alerts.first.daysLeft, lessThan(0));
    });

    test('a batch expiring today is not expired yet', () {
      final alerts =
          computeExpiryAlerts(drinks: [drink(name: 'Today', expiry: today)]);
      expect(alerts, hasLength(1));
      expect(alerts.first.isExpired, isFalse);
      expect(alerts.first.daysLeft, 0);
    });

    test('joins the forecast so the alert carries expected demand', () {
      final alerts = computeExpiryAlerts(
        drinks: [
          drink(
              name: 'Beer',
              expiry: today.add(const Duration(days: 5)),
              stock: 24),
        ],
        forecast: forecastWith([item('Beer', demand: 18.5, order: 12)]),
      );
      expect(alerts, hasLength(1));
      expect(alerts.first.forecastDemand, 18.5);
      expect(alerts.first.recommendedOrder, 12);
      expect(alerts.first.currentStock, 24);
      expect(alerts.first.confidence, 0.5);
    });

    test('matches the forecast case-insensitively', () {
      final alerts = computeExpiryAlerts(
        drinks: [
          drink(name: '  beer ', expiry: today.add(const Duration(days: 2))),
        ],
        forecast: forecastWith([item('Beer', demand: 9)]),
      );
      expect(alerts.first.forecastDemand, 9);
    });

    test('still alerts without a forecast (demand left at zero)', () {
      final alerts = computeExpiryAlerts(
        drinks: [drink(name: 'Beer', expiry: today.add(const Duration(days: 2)))],
      );
      expect(alerts.first.forecastDemand, 0);
      expect(alerts.first.recommendedOrder, 0);
    });

    test('sorts the most urgent batch first and keeps every batch', () {
      final alerts = computeExpiryAlerts(drinks: [
        drink(name: 'Later', id: 'b', expiry: today.add(const Duration(days: 20))),
        drink(name: 'Gone', id: 'c', expiry: today.subtract(const Duration(days: 1))),
        drink(name: 'Soon', id: 'a', expiry: today.add(const Duration(days: 2))),
      ]);
      expect(alerts.map((a) => a.drinkName).toList(), ['Gone', 'Soon', 'Later']);
    });

    test('the dedupe key identifies the batch, not just the drink', () {
      final alert = computeExpiryAlerts(drinks: [
        drink(name: 'Beer', id: 'd9', expiry: today.add(const Duration(days: 3))),
      ]).first;
      expect(alert.dedupeKey.startsWith('d9|'), isTrue);
      expect(alert.dedupeKey.split('|').length, 2);
    });
  });

  group('expiryAlertMessage', () {
    test('includes the days left and the expected demand', () {
      final alert = computeExpiryAlerts(
        drinks: [drink(name: 'Beer', expiry: today.add(const Duration(days: 6)))],
        forecast: forecastWith([item('Beer', demand: 12.5, order: 4)]),
      ).first;

      final message = expiryAlertMessage(alert, t);
      expect(message, contains('Beer'));
      expect(message, contains('day(s) left'));
      expect(message, contains('expected demand: 12.5'));
      expect(message, contains('suggested order: 4'));
    });

    test('says already expired for a past batch', () {
      final alert = computeExpiryAlerts(drinks: [
        drink(name: 'Old', expiry: today.subtract(const Duration(days: 2))),
      ]).first;

      final message = expiryAlertMessage(alert, t);
      expect(message, contains('already expired'));
      expect(message, isNot(contains('day(s) left')));
    });

    test('omits the demand part when there is no forecast', () {
      final alert = computeExpiryAlerts(drinks: [
        drink(name: 'Beer', expiry: today.add(const Duration(days: 6))),
      ]).first;

      final message = expiryAlertMessage(alert, t);
      expect(message, isNot(contains('expected demand')));
    });
  });
}