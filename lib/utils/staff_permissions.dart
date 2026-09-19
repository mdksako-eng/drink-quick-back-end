// utils/staff_permissions.dart
// Pure staff-management rules, mirroring utils/staffPermissions.js on the
// backend so the UI never offers an action the API would refuse.
//
// A company has exactly one owner (companies.owner_id). The owner account sits
// at the top of the hierarchy: a co-manager may not edit it — only the owner
// themselves or a platform Administrator may.

class StaffPermissions {
  StaffPermissions._();

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
