// test/owner_permissions_test.dart
// A co-manager (Manager without the owner flag) must never reach company data
// management, branding or staff-level owner operations.
import 'package:flutter_test/flutter_test.dart';
import 'package:drinks_calculator_fixed/utils/owner_permissions.dart';

void main() {
  group('data management / branding', () {
    test('the owner manager may manage both', () {
      expect(
        OwnerPermissions.canManageCompanyData(role: 'manager', isOwner: true),
        isTrue,
      );
      expect(
        OwnerPermissions.canManageBranding(role: 'manager', isOwner: true),
        isTrue,
      );
    });

    test('a co-manager may manage neither', () {
      expect(
        OwnerPermissions.canManageCompanyData(role: 'manager', isOwner: false),
        isFalse,
      );
      expect(
        OwnerPermissions.canManageBranding(role: 'manager', isOwner: false),
        isFalse,
      );
    });

    test('a manager with no owner information is treated as a co-manager', () {
      expect(OwnerPermissions.canManageCompanyData(role: 'manager'), isFalse);
      expect(OwnerPermissions.canManageBranding(role: 'manager'), isFalse);
    });

    test('staff and customers never manage company data', () {
      for (final role in ['staff', 'customer', '']) {
        expect(OwnerPermissions.canManageCompanyData(role: role, isOwner: false),
            isFalse);
        expect(OwnerPermissions.canManageBranding(role: role, isOwner: false),
            isFalse);
      }
    });

    test('a platform admin always may', () {
      for (final role in ['admin', 'administrator']) {
        expect(OwnerPermissions.canManageCompanyData(role: role), isTrue);
        expect(OwnerPermissions.canManageBranding(role: role), isTrue);
      }
    });
  });

  group('billing / payments', () {
    test('any manager (owner or not) can manage billing', () {
      expect(OwnerPermissions.canManageBilling(role: 'manager'), isTrue);
      expect(
        OwnerPermissions.canManageBilling(role: 'manager', isOwner: false),
        isTrue,
      );
    });

    test('staff and customers cannot', () {
      expect(OwnerPermissions.canManageBilling(role: 'staff'), isFalse);
      expect(OwnerPermissions.canManageBilling(role: 'customer'), isFalse);
    });

    test('payments follow the same rule as billing', () {
      expect(OwnerPermissions.canManagePayments(role: 'manager'), isTrue);
      expect(OwnerPermissions.canManagePayments(role: 'staff'), isFalse);
      expect(OwnerPermissions.canManagePayments(role: 'administrator'), isTrue);
    });
  });

  group('role checks', () {
    test('isAdminRole accepts both spellings only', () {
      expect(OwnerPermissions.isAdminRole('admin'), isTrue);
      expect(OwnerPermissions.isAdminRole('administrator'), isTrue);
      expect(OwnerPermissions.isAdminRole('Admin'), isFalse);
      expect(OwnerPermissions.isAdminRole(null), isFalse);
    });

    test('isCompanyOwner requires exactly true', () {
      expect(OwnerPermissions.isCompanyOwner(true), isTrue);
      expect(OwnerPermissions.isCompanyOwner(false), isFalse);
      expect(OwnerPermissions.isCompanyOwner(null), isFalse);
    });
  });
}
