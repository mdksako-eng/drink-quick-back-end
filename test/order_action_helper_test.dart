// test/order_action_helper_test.dart
// The correction button on an invoice card: Void, Restore, or the stock-free
// Cancel that records the missing trace on a rolled-back sale. The rule lives in
// lib/utils so it can be tested without pumping the invoice history.
import 'package:flutter_test/flutter_test.dart';
import 'package:drinks_calculator_fixed/utils/order_action_helper.dart';

void main() {
  group('a sale that counts', () {
    test('offers Void, labelled as a void', () {
      final action =
          OrderActionHelper.actionFor(isActive: true, isVoided: false);
      expect(action, OrderAction.voidOrder);
      expect(OrderActionHelper.labelKey(action), 'voidOrder');
      expect(
        OrderActionHelper.countsAsSale(isActive: true, isVoided: false),
        isTrue,
      );
    });
  });

  group('a voided sale', () {
    test('offers Restore', () {
      final action =
          OrderActionHelper.actionFor(isActive: false, isVoided: true);
      expect(action, OrderAction.restoreOrder);
      expect(OrderActionHelper.labelKey(action), 'restoreOrder');
      expect(
        OrderActionHelper.countsAsSale(isActive: false, isVoided: true),
        isFalse,
      );
    });

    test('is never offered as a cancel, whatever is_active claims', () {
      // The regression: cancelling a voided row would skip restoring its stock.
      expect(
        OrderActionHelper.actionFor(isActive: false, isVoided: true),
        isNot(OrderAction.cancelOrder),
      );
      expect(
        OrderActionHelper.actionFor(isActive: true, isVoided: true),
        OrderAction.restoreOrder,
      );
    });
  });

  group('a sale the till cancelled (inactive, no void trace)', () {
    test('offers Void again so the trace gets recorded — never Restore', () {
      // The old build drew this row as "Restore" and then voided it, restoring
      // stock the crashed sale had never taken.
      final action =
          OrderActionHelper.actionFor(isActive: false, isVoided: false);
      expect(action, OrderAction.cancelOrder);
      expect(action, isNot(OrderAction.restoreOrder));
      expect(OrderActionHelper.labelKey(action), 'voidOrder');
    });

    test('does not count as a sale', () {
      expect(
        OrderActionHelper.countsAsSale(isActive: false, isVoided: false),
        isFalse,
      );
    });
  });
}
