// utils/staff_permissions.dart
// Pure staff-management rules, mirroring utils/staffPermissions.js on the
// backend so the UI never offers an action the API would refuse.
//
// A company has exactly one owner (companies.owner_id). The owner account sits
// at the top of the hierarchy: a co-manager may not edit it — only the owner
// themselves or a platform Administrator may.

class StaffPermissions {
  StaffPermissions._();

  // ============================================================
  // ROLES — one place that knows how a role is spelled
  // ============================================================
  // Roles arrive in mixed case depending on where they come from: the database
  // stores 'Manager', the login payload keeps that, and several screens lower-case
  // it before comparing. Two conventions in one file is how a menu entry silently
  // disappears, so every check goes through these helpers and never compares a raw
  // role string again.
  //
  // 'Owner' is accepted as a manager even though the app never assigns it: the
  // backend already treats it as one (utils/paymentChannels' sibling gate and
  // utils/twoFactor.js both list it), so ignoring it here would hide the manager
  // entries from a company owner whose row was set to it by hand.

  /// Lower-cased, trimmed role. '' when there is none.
  static String normalizeRole(String? role) => (role ?? '').trim().toLowerCase();

  /// Platform administrator (either spelling the API accepts).
  static bool isAdminRole(String? role) {
    final r = normalizeRole(role);
    return r == 'admin' || r == 'administrator';
  }

  /// Manager or company owner — the roles that commit the company's money.
  static bool isManagerRole(String? role) {
    final r = normalizeRole(role);
    return r == 'manager' || r == 'owner';
  }

  /// The company owner specifically.
  static bool isOwnerRole(String? role) => normalizeRole(role) == 'owner';

  /// Shop-floor staff.
  static bool isStaffRole(String? role) => normalizeRole(role) == 'staff';

  /// A customer account (buys, does not manage).
  static bool isCustomerRole(String? role) => normalizeRole(role) == 'customer';

  /// True when the staff row belongs to the company owner.
  /// The backend marks the row with `isOwner` in GET /api/users.
  static bool isOwnerRow(Map<String, dynamic> staff) =>
      staff['isOwner'] == true;

  /// Whether the signed-in user may edit [staff].
  ///
  /// [viewerId] is the current user's id, [viewerIsAdmin] whether they are a
  /// platform Administrator and [viewerIsOwner] their own owner flag (both come
  /// from the login payload). The API enforces exactly the same rule.
  static bool canEdit({
    required Map<String, dynamic> staff,
    required String? viewerId,
    required bool viewerIsAdmin,
    bool viewerIsOwner = false,
  }) {
    if (!isOwnerRow(staff)) return true;
    if (viewerIsAdmin || viewerIsOwner) return true;
    final rowId = staff['id']?.toString();
    if (rowId == null || rowId.isEmpty || viewerId == null) return false;
    return rowId == viewerId;
  }
}
