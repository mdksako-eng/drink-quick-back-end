// test/order_correction_helper_test.dart
// The UI gate must match the backend rule exactly, or a cashier taps Void and gets
// a 403. Manager: any sale. Staff: their own sale, within 10 minutes.
import 'package:flutter_test/flutter_test.dart';
import 'package:drinks_calculator_fixed/utils/order_correction_helper.dart';

final now = DateTime(2026, 10, 21, 20, 0);

bool can({
  String? role = 'Staff',
  String? username = 'onean',
  String? soldBy = 'onean',
  DateTime? soldAt,
  Duration? window,
}) =>
    OrderCorrection.canCorrect(
      role: role,
      username: username,
      orderStaffName: soldBy,
      soldAt: soldAt ?? now.subtract(const Duration(minutes: 1)),
      now: now,
      window: window ?? OrderCorrection.staffWindow,
    );

void main() {
  group('managers', () {
    test('may correct any sale, whatever its age', () {
      expect(can(role: 'Manager', soldBy: 'someone-else',
          soldAt: now.subtract(const Duration(days: 3))), isTrue);
      expect(can(role: 'Administrator', soldBy: null), isTrue);
      expect(can(role: 'admin', soldBy: ''), isTrue);
    });
  });

  group('staff', () {
    test('may correct their own sale inside the window', () {
      expect(can(soldAt: now.subtract(const Duration(minutes: 5))), isTrue);
    });

    test('may not after the window', () {
      expect(can(soldAt: now.subtract(const Duration(minutes: 11))), isFalse);
    });

    test('another cashier\'s sale is refused', () {
      expect(can(soldBy: 'ama'), isFalse);
    });

    test('an unknown seller is refused', () {
      expect(can(soldBy: null), isFalse);
      expect(can(soldBy: ''), isFalse);
      expect(can(username: null), isFalse);
    });

    test('a missing sale date is refused', () {
      expect(
          OrderCorrection.canCorrect(
            role: 'Staff',
            username: 'onean',
            orderStaffName: 'onean',
            soldAt: null,
            now: now,
          ),
          isFalse);
    });

    test('a device clock behind the sale is refused (no infinite window)', () {
      expect(can(soldAt: now.add(const Duration(minutes: 5))), isFalse);
    });

    test('the boundary is inclusive', () {
      expect(can(soldAt: now.subtract(const Duration(minutes: 10))), isTrue);
    });
  });

  group('other roles and custom windows', () {
    test('a customer or unknown role never corrects', () {
      expect(can(role: 'Customer'), isFalse);
      expect(can(role: null), isFalse);
      expect(can(role: ''), isFalse);
    });

    test('the window is configurable', () {
      expect(can(soldAt: now.subtract(const Duration(minutes: 20))), isFalse);
      expect(
          can(
              soldAt: now.subtract(const Duration(minutes: 20)),
              window: const Duration(minutes: 30)),
          isTrue);
    });
  });
}
