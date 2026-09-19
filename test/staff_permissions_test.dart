// test/staff_permissions_test.dart
// Guards the "a co-manager must not edit the owner" rule. The Dart helper
// mirrors utils/staffPermissions.js on the backend, so these expectations are
// the contract both sides must satisfy.
import 'package:flutter_test/flutter_test.dart';

import 'package:drinks_calculator_fixed/utils/staff_permissions.dart';

void main() {
  final ownerRow = <String, dynamic>{'id': 3, 'role': 'Manager', 'isOwner': true};
  final staffRow = <String, dynamic>{'id': 11, 'role': 'Staff', 'isOwner': false};

  group('isOwnerRow', () {
    test('detects the owner flag', () {
      expect(StaffPermissions.isOwnerRow(ownerRow), isTrue);
      expect(StaffPermissions.isOwnerRow(staffRow), isFalse);
    });

    test('treats a missing flag as not the owner', () {
      expect(StaffPermissions.isOwnerRow(<String, dynamic>{'id': 4}), isFalse);
    });
  });

  group('canEdit - owner protection', () {
    test('a co-manager (another manager) cannot edit the owner', () {
      expect(
        StaffPermissions.canEdit(
          staff: ownerRow,
          viewerId: '9',
          viewerIsAdmin: false,
          viewerIsOwner: false,
        ),
        isFalse,
      );
    });

    test('the owner can edit their own account', () {
      expect(
        StaffPermissions.canEdit(
          staff: ownerRow,
          viewerId: '3',
          viewerIsAdmin: false,
          viewerIsOwner: true,
        ),
        isTrue,
      );
    });

    test('the owner can edit their own account even without the owner flag', () {
      expect(
        StaffPermissions.canEdit(
          staff: ownerRow,
          viewerId: '3',
          viewerIsAdmin: false,
        ),
        isTrue,
      );
    });

    test('an administrator can edit the owner', () {
      expect(
        StaffPermissions.canEdit(
          staff: ownerRow,
          viewerId: '1',
          viewerIsAdmin: true,
        ),
        isTrue,
      );
    });

    test('a co-manager can still edit staff members', () {
      expect(
        StaffPermissions.canEdit(
          staff: staffRow,
          viewerId: '9',
          viewerIsAdmin: false,
        ),
        isTrue,
      );
    });

    test('numeric and string ids are compared consistently', () {
      expect(
        StaffPermissions.canEdit(
          staff: <String, dynamic>{'id': '3', 'isOwner': true},
          viewerId: '3',
          viewerIsAdmin: false,
        ),
        isTrue,
      );
    });

    test('a malformed row never grants the owner edit right', () {
      expect(
        StaffPermissions.canEdit(
          staff: <String, dynamic>{'isOwner': true},
          viewerId: '3',
          viewerIsAdmin: false,
        ),
        isFalse,
      );
      expect(
        StaffPermissions.canEdit(
          staff: ownerRow,
          viewerId: null,
          viewerIsAdmin: false,
        ),
        isFalse,
      );
    });
  });
}