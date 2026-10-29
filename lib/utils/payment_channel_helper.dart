// utils/payment_channel_helper.dart
// Which rail a subscription is charged on (card / MTN MoMo / Orange Money) and
// what each one is called. Pure — unit tested — so the subscription screen only
// renders what this decides.
//
// Every rail is always offered: CamerPay publishes no per-rail availability list
// (the account decides), so its own checkout page is the authority and refuses
// with a reason when it cannot charge a method.
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

