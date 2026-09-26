// test/payment_channel_helper_test.dart
// The three subscription rails (card / MTN / Orange): which is offered, what the
// backend is asked for, and what happens when the server has no opinion.
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

  group('when the server has no opinion', () {
    test('unknown offers everything', () {
      kPayRails.forEach((rail) {
        expect(PayChannelAvailability.unknown.allows(rail), isTrue);
      });
    });

    test('a response without a supported map stays unknown', () {
      final availability = PayChannelAvailability.fromJson(const {});
      expect(availability.known, isFalse);
      expect(availability.allows(PayRail.mtn), isTrue);
    });

    test('known:true but supported:null stays unknown', () {
      final availability = PayChannelAvailability.fromJson(const {
        'known': true,
        'supported': null,
      });
      expect(availability.known, isFalse);
      expect(availability.allows(PayRail.orange), isTrue);
    });
  });

  group('when the server reports the account', () {
    test('Mobile money on the account is offered', () {
      final availability = PayChannelAvailability.fromJson(const {
        'known': true,
        'supported': {'card': false, 'mtn': true, 'orange': true},
      });
      expect(availability.known, isTrue);
      expect(availability.mtn, isTrue);
      expect(availability.orange, isTrue);
      expect(availability.hasNotchpayCard, isFalse);
    });

    test('a Mobile Money rail the account lacks is hidden', () {
      final availability = PayChannelAvailability.fromJson(const {
        'known': true,
        'supported': {'card': false, 'mtn': true, 'orange': false},
      });
      expect(availability.allows(PayRail.mtn), isTrue);
      expect(availability.allows(PayRail.orange), isFalse);
    });

    test('card stays offered even without a card channel on the account', () {
      final availability = PayChannelAvailability.fromJson(const {
        'known': true,
        'supported': {'card': false, 'mtn': false, 'orange': false},
      });
      // Card also runs through the app's card provider, so it is never hidden.
      expect(availability.allows(PayRail.card), isTrue);
      expect(availability.hasNotchpayCard, isFalse);
    });

    test('a card channel on the account is remembered', () {
      final availability = PayChannelAvailability.fromJson(const {
        'known': true,
        'supported': {'card': true, 'mtn': true, 'orange': true},
      });
      expect(availability.hasNotchpayCard, isTrue);
      expect(availability.allows(PayRail.card), isTrue);
    });

    test('supported without a known flag is still trusted', () {
      final availability = PayChannelAvailability.fromJson(const {
        'supported': {'card': false, 'mtn': false, 'orange': true},
      });
      expect(availability.known, isTrue);
      expect(availability.allows(PayRail.orange), isTrue);
      expect(availability.allows(PayRail.mtn), isFalse);
    });
  });
}
