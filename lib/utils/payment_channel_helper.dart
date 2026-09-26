// utils/payment_channel_helper.dart
// Which rail a subscription is charged on (card / MTN MoMo / Orange Money) and
// whether the platform account can actually charge it. Pure — unit tested — so
// the subscription screen only renders what this decides.
//
// The backend reports availability from the payment provider's own channel list
// (`GET /subscriptions/notchpay-channels`). When it cannot tell us (`known`
// false) every rail stays offered: hiding a working payment method is worse
// than letting the provider refuse it.
import 'package:flutter/material.dart';

/// A way to pay for a subscription.
enum PayRail { card, mtn, orange }

/// Every rail, in the order the upgrade sheet shows them.
const List<PayRail> kPayRails = [PayRail.card, PayRail.mtn, PayRail.orange];

extension PayRailInfo on PayRail {
  /// Translation key for the rail's label.
  String get labelKey {
    switch (this) {
      case PayRail.card:
        return 'payByCard';
      case PayRail.mtn:
        return 'payWithMomo';
      case PayRail.orange:
        return 'payWithOrange';
    }
  }

  /// Icon shown next to the rail.
  IconData get icon {
    switch (this) {
      case PayRail.card:
        return Icons.credit_card;
      case PayRail.mtn:
      case PayRail.orange:
        return Icons.phone_android;
    }
  }

  /// What the backend expects in the initiate request. It resolves 'card' to the
  /// account's card channel when there is one, and otherwise opens the checkout
  /// page where card is one of the choices.
  String get channel {
    switch (this) {
      case PayRail.card:
        return 'card';
      case PayRail.mtn:
        return 'mtn';
      case PayRail.orange:
        return 'orange';
    }
  }
}

/// What the server says about the platform's payment account.
class PayChannelAvailability {
  const PayChannelAvailability({
    this.known = false,
    this.hasNotchpayCard = false,
    this.mtn = true,
    this.orange = true,
  });

  /// False when the server could not ask the provider — treat as "no opinion".
  final bool known;

  /// True when the provider account itself has a card channel (so a card payment
  /// can be locked straight to it instead of opening the general checkout).
  final bool hasNotchpayCard;

  final bool mtn;
  final bool orange;

  /// Used whenever the server has no opinion.
  static const PayChannelAvailability unknown = PayChannelAvailability();

  factory PayChannelAvailability.fromJson(Map<String, dynamic> json) {
    final supported = json['supported'];
    if (supported is! Map) return unknown;
    final map = Map<String, dynamic>.from(supported);
    return PayChannelAvailability(
      known: json['known'] == true || map.isNotEmpty,
      hasNotchpayCard: map['card'] == true,
      mtn: map['mtn'] == true,
      orange: map['orange'] == true,
    );
  }

  /// May this rail be offered?
  ///
  /// Card is always offered: card payments also run through the app's card
  /// provider, so a missing card channel on the mobile-money account is not
  /// enough reason to hide the button. Mobile Money is only hidden when the
  /// provider positively confirms it is not enabled.
  bool allows(PayRail rail) {
    if (!known) return true;
    switch (rail) {
      case PayRail.card:
        return true;
      case PayRail.mtn:
        return mtn;
      case PayRail.orange:
        return orange;
    }
  }
}
