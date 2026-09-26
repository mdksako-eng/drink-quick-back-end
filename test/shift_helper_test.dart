// test/shift_helper_test.dart
// The cash-up rules behind the Z-report, mirroring the backend's
// utils/shiftMath.js. No widgets are pumped here.
import 'package:flutter_test/flutter_test.dart';
import 'package:drinks_calculator_fixed/models/shift_model.dart';
import 'package:drinks_calculator_fixed/utils/shift_helper.dart';

void main() {
  group('expected cash', () {
    test('is float + collected - payouts', () {
      expect(
        ShiftHelper.expectedCash(openingFloat: 5000, collected: 3000),
        8000,
      );
      expect(
        ShiftHelper.expectedCash(
          openingFloat: 5000,
          collected: 3000,
          payouts: 1000,
        ),
        7000,
      );
    });

    test('rounds away floating point noise', () {
      expect(ShiftHelper.expectedCash(openingFloat: 0.1, collected: 0.2), 0.3);
    });
  });

  group('variance', () {
    test('negative when the till is short, positive when it is over', () {
      expect(ShiftHelper.variance(counted: 8000, expectedCash: 10000), -2000);
      expect(ShiftHelper.isShort(-2000), isTrue);
      expect(ShiftHelper.isOver(500), isTrue);
      expect(ShiftHelper.isOver(-2000), isFalse);
    });

    test('a cent-level difference still counts as balanced', () {
      expect(ShiftHelper.balanced(0), isTrue);
      expect(ShiftHelper.balanced(-0.001), isTrue);
      expect(ShiftHelper.balanced(-0.02), isFalse);
      expect(ShiftHelper.balanced(null), isFalse);
    });
  });

  group('who may close a shift', () {
    test('the staff member who opened it', () {
      expect(
        ShiftHelper.canClose(role: 'Staff', userId: 11, shiftStaffUserId: 11),
        isTrue,
      );
    });

    test('not another staff member', () {
      expect(
        ShiftHelper.canClose(role: 'Staff', userId: 12, shiftStaffUserId: 11),
        isFalse,
      );
    });

    test('a manager or administrator closes anyone', () {
      expect(
        ShiftHelper.canClose(role: 'Manager', userId: 9, shiftStaffUserId: 11),
        isTrue,
      );
      expect(
        ShiftHelper.canClose(
          role: 'Administrator',
          userId: 1,
          shiftStaffUserId: 11,
        ),
        isTrue,
      );
    });

    test('the owner always may', () {
      expect(
        ShiftHelper.canClose(
          role: 'Staff',
          userId: 12,
          shiftStaffUserId: 11,
          isOwner: true,
        ),
        isTrue,
      );
    });
  });

  group('labels', () {
    test('shift status', () {
      expect(ShiftHelper.statusKey('open'), 'shiftStatusOpen');
      expect(ShiftHelper.statusKey('closed'), 'shiftStatusClosed');
      expect(ShiftHelper.statusKey(null), 'shiftStatusOpen');
    });

    test('variance wording', () {
      expect(ShiftHelper.varianceKey(0), 'shiftBalanced');
      expect(ShiftHelper.varianceKey(-500), 'shiftShort');
      expect(ShiftHelper.varianceKey(500), 'shiftOver');
      expect(ShiftHelper.varianceKey(null), 'shiftBalanced');
    });

    test('durations', () {
      final opened = DateTime(2026, 1, 1, 8);
      expect(
        ShiftHelper.durationLabel(
          opened,
          closedAt: DateTime(2026, 1, 1, 11, 25),
        ),
        '3h 25m',
      );
      expect(
        ShiftHelper.durationLabel(opened, closedAt: DateTime(2026, 1, 1, 8, 40)),
        '40m',
      );
      expect(ShiftHelper.durationLabel(null), '-');
    });
  });

  group('the shift window', () {
    final opened = DateTime(2026, 1, 1, 8);
    final closed = DateTime(2026, 1, 1, 16);

    test('an order inside the window belongs to the shift', () {
      expect(
        ShiftHelper.coversOrder(
          openedAt: opened,
          closedAt: closed,
          orderTime: DateTime(2026, 1, 1, 12),
        ),
        isTrue,
      );
    });

    test('an order after the close does not', () {
      expect(
        ShiftHelper.coversOrder(
          openedAt: opened,
          closedAt: closed,
          orderTime: DateTime(2026, 1, 1, 16, 1),
        ),
        isFalse,
      );
    });

    test('a running shift covers everything after it opened', () {
      expect(
        ShiftHelper.coversOrder(openedAt: opened, orderTime: DateTime(2026, 1, 2)),
        isTrue,
      );
      expect(ShiftHelper.coversOrder(openedAt: null, orderTime: opened), isFalse);
    });
  });

  group('parsing server rows', () {
    test('NUMERIC strings and the method breakdown are read', () {
      final shift = Shift.fromJson(const {
        'id': 5,
        'staff_user_id': 11,
        'staff_name': 'Bih',
        'status': 'closed',
        'opening_float': '5000.00',
        'cash_counted': '23000.00',
        'cash_expected': '25000.00',
        'variance': '-2000.00',
        'order_count': 4,
        'payment_breakdown': {'MTN': '4000.00'},
        'closed_at': '2026-01-01T16:00:00.000Z',
      });
      expect(shift.id, 5);
      expect(shift.isOpen, isFalse);
      expect(shift.openingFloat, 5000);
      expect(shift.variance, -2000);
      expect(shift.orderCount, 4);
      expect(shift.paymentBreakdown['MTN'], 4000);
      expect(shift.closedAt, isNotNull);
    });

    test('a summary reports short, balanced and over', () {
      final short = ShiftSummary.fromJson(const {
        'expectedCash': 25000,
        'counted': 23000,
        'variance': -2000,
      });
      expect(short.isShort, isTrue);
      expect(short.balanced, isFalse);

      final balanced = ShiftSummary.fromJson(const {
        'expectedCash': 1000,
        'counted': 1000,
        'variance': 0,
      });
      expect(balanced.balanced, isTrue);

      final over = ShiftSummary.fromJson(const {
        'expectedCash': 1000,
        'counted': 1300,
        'variance': 300,
      });
      expect(over.isOver, isTrue);
    });

    test('an open shift has no count or variance yet', () {
      final summary = ShiftSummary.fromJson(const {'expectedCash': 5000});
      expect(summary.counted, isNull);
      expect(summary.variance, isNull);
      expect(summary.balanced, isFalse);
    });
  });
}