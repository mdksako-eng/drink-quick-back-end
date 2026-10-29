// test/payment_channel_helper_test.dart
// The three subscription rails (card / MTN / Orange): what the sheet offers and
// what the backend is asked for. There is no availability list to test — CamerPay
// publishes none, so every rail is always offered.
import 'package:flutter_test/flutter_test.dart';
import 'package:drinks_calculator_fixed/utils/payment_channel_helper.dart';

void main() {
  group('the rails we offer', () {
    test('card, MTN and Orange, in sheet order', () {
      expect(kPayRails, [PayRail.card, PayRail.mtn, PayRail.orange]);
    });

    test('each rail sends the channel the backend understands', () {
      expect(PayRail.card.channel, 'card');
      expect(PayRail.mtn.channel, 'mtn');
      expect(PayRail.orange.channel, 'orange');
    });

    test('each rail has its own label key, so EN/FR stay in i18n', () {
      expect(PayRail.card.labelKey, 'payByCard');
      expect(PayRail.mtn.labelKey, 'payWithMomo');
      expect(PayRail.orange.labelKey, 'payWithOrange');
    });

    test('every rail has an icon', () {
      kPayRails.forEach((rail) => expect(rail.icon, isNotNull));
    });
  });
}
