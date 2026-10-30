// test/drawer_navigation_test.dart
// The drawer's grouping, its search filter, and the role helpers that decide which
// entries exist. All pure, so it is tested here rather than by pumping a widget.
import 'package:flutter_test/flutter_test.dart';
import 'package:drinks_calculator_fixed/utils/drawer_navigation.dart';
import 'package:drinks_calculator_fixed/utils/staff_permissions.dart';

void main() {
  group('the sections', () {
    test('daily work comes first, support last', () {
      expect(kDrawerGroupOrder.first, DrawerGroup.daily);
      expect(kDrawerGroupOrder.last, DrawerGroup.support);
    });

    test('every section has its own header key', () {
      final keys = kDrawerGroupOrder.map(drawerGroupLabelKey).toList();
      expect(keys.toSet().length, keys.length, reason: 'two sections share a key');
      expect(keys, contains('menuMain'));
      expect(keys, contains('menuManagement'));
      expect(keys, contains('menuSetup'));
      expect(keys, contains('menuSupport'));
    });

    test('the two keys that were dead are used now', () {
      final keys = kDrawerGroupOrder.map(drawerGroupLabelKey).toList();
      expect(keys.where((k) => k == 'menuManagement').length, 1);
      expect(keys.where((k) => k == 'menuSupport').length, 1);
    });
  });

  group('the search filter', () {
    test('an empty query shows everything', () {
      expect(drawerSearchMatches('', 'Inventory'), isTrue);
      expect(drawerSearchMatches('   ', 'Inventory'), isTrue);
    });

    test('it matches a fragment, ignoring case', () {
      expect(drawerSearchMatches('invent', 'Inventory'), isTrue);
      expect(drawerSearchMatches('INVENT', 'Inventory'), isTrue);
      expect(drawerSearchMatches('ory', 'Inventory'), isTrue);
    });

    test('it ignores accents, because nobody types them', () {
      expect(drawerSearchMatches('reapprovisionnement', 'Réapprovisionnement'), isTrue);
      expect(drawerSearchMatches('gerant', 'Gérant'), isTrue);
      expect(drawerSearchMatches('configuration', 'CONFIGURATION'), isTrue);
    });

    test('it really filters', () {
      expect(drawerSearchMatches('variance', 'Inventory'), isFalse);
      expect(drawerSearchMatches('zzz', 'Inventory'), isFalse);
    });
  });

  group('roles are read one way only', () {
    test('case and padding do not matter', () {
      expect(StaffPermissions.isManagerRole('Manager'), isTrue);
      expect(StaffPermissions.isManagerRole('manager'), isTrue);
      expect(StaffPermissions.isManagerRole(' MANAGER '), isTrue);
      expect(StaffPermissions.isStaffRole('Staff'), isTrue);
      expect(StaffPermissions.isStaffRole('STAFF'), isTrue);
      expect(StaffPermissions.isAdminRole('Administrator'), isTrue);
      expect(StaffPermissions.isAdminRole('admin'), isTrue);
    });

    test('the company owner counts as a manager', () {
      expect(StaffPermissions.isManagerRole('Owner'), isTrue);
      expect(StaffPermissions.isOwnerRole('owner'), isTrue);
      // ...but an owner is neither an admin nor shop-floor staff.
      expect(StaffPermissions.isAdminRole('Owner'), isFalse);
      expect(StaffPermissions.isStaffRole('Owner'), isFalse);
    });

    test('nothing, and nonsense, are nobody', () {
      expect(StaffPermissions.isManagerRole(null), isFalse);
      expect(StaffPermissions.isManagerRole(''), isFalse);
      expect(StaffPermissions.isManagerRole('barista'), isFalse);
      expect(StaffPermissions.isCustomerRole('Customer'), isTrue);
      expect(StaffPermissions.isCustomerRole('Manager'), isFalse);
    });
  });
}
