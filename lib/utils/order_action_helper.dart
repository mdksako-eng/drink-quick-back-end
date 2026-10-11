// utils/order_action_helper.dart
// What the correction button on an invoice card does, and what it is called.
//
// Kept pure and outside the widget so the rule is unit tested. The card used to
// draw its icon and its dialog from `isActive` while the action it ran was chosen
// from `isVoided`, so a row cancelled by an older build (inactive, with no void
// trace) offered "Restore" and then voided the sale — putting back stock that had
// never left the shelf.
//
// The two flags come from different flows:
//   * a VOID sets both (manager, stock goes back, who/when/why kept), and
//   * a CANCEL sets only `is_active = false` (the till rolled a sale back after a
//     refused stock commit).
// So `isVoided` decides the action, and `isActive` only decides whether the card
// still counts as a sale.
enum OrderAction {
  /// Counts as a sale: a manager may void it (the stock goes back to the shelf).
  voidOrder,

  /// Voided: it can be put back (the stock comes off the shelf again).
  restoreOrder,

  /// Cancelled without a void trace: only the missing trace is recorded. Never a
  /// void — that would restore stock this sale never took.
  cancelOrder,
}

class OrderActionHelper {
  OrderActionHelper._();

  /// Does this invoice still count as a sale?
  static bool countsAsSale({required bool isActive, required bool isVoided}) =>
      isActive && !isVoided;

  /// Which correction the button offers. A void trace wins: a row that carries
  /// one can always be restored, whatever its `is_active` says.
  static OrderAction actionFor({
    required bool isActive,
    required bool isVoided,
  }) {
    if (isVoided) return OrderAction.restoreOrder;
    if (!isActive) return OrderAction.cancelOrder;
    return OrderAction.voidOrder;
  }

  /// The i18n key for the button and the dialog title.
  static String labelKey(OrderAction action) {
    switch (action) {
      case OrderAction.restoreOrder:
        return 'restoreOrder';
      case OrderAction.voidOrder:
      case OrderAction.cancelOrder:
        return 'voidOrder';
    }
  }
}
