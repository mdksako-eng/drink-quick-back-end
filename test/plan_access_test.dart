// test/plan_access_test.dart
// A platform administrator must never be locked out of a feature by their
// company's plan: the backend already lets administrators through `requirePlan`,
// so an app that hides the screen only hides a door that is open on the server.
// These tests pin that rule and, just as importantly, that it does not leak to
// anyone else.
import 'package:flutter_test/flutter_test.dart';
import 'package:drinks_calculator_fixed/utils/plan_gate_logic.dart';

void main() {
  group('featureAccessAllowed', () {
    test('an admin gets in even when the plan grants nothing', () {
      expect(featureAccessAllowed(isAdmin: true, planGrants: false), isTrue);
    });

    test('an admin with a paid plan gets in', () {
      expect(featureAccessAllowed(isAdmin: true, planGrants: true), isTrue);
    });

    test('a non-admin with the plan gets in', () {
      expect(featureAccessAllowed(isAdmin: false, planGrants: true), isTrue);
    });

    test('a non-admin without the plan is refused', () {
      expect(featureAccessAllowed(isAdmin: false, planGrants: false), isFalse);
    });

    test('the bypass is admin-only — an owner or manager is still gated', () {
      // Owners/managers reach this function with isAdmin false; the plan decides.
      expect(featureAccessAllowed(isAdmin: false, planGrants: false), isFalse);
    });
  });
}
