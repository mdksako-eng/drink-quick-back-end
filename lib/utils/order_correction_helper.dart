// utils/order_correction_helper.dart
// Mirrors backend/utils/orderVoid.js so the UI never offers an action the API
// would refuse.
//
// Rule: a manager / administrator / owner may correct any sale. A STAFF member may
// correct a sale they rang themselves, but only within 10 minutes — the mistake is
// noticed at once, and waiting for a manager to walk over is worse for the customer.
// The correction stays auditable: it is recorded with who/when/why and shows on the
// shift report, so a manager sees every one.
class OrderCorrection {
  OrderCorrection._();

  /// Must stay equal to STAFF_CORRECTION_WINDOW_MS on the backend.
  static const Duration staffWindow = Duration(minutes: 10);

  static bool isManagerRole(String? role) {
    final value = (role ?? '').trim().toLowerCase();
    return value == 'manager' || value == 'administrator' || value == 'admin';
  }

  /// Whether [username] may void / re-invoice this sale.
  static bool canCorrect({
    required String? role,
    required String? username,
    required String? orderStaffName,
    required DateTime? soldAt,
    required DateTime now,
    Duration window = staffWindow,
  }) {
    if (isManagerRole(role)) return true;

    // Only a STAFF account gets the correction window. Anything else (customer,
    // unknown role) never corrects a sale — the backend checks the same thing, and
    // without this line any role could void its own recent sale.
    final isStaff = (role ?? '').trim().toLowerCase() == 'staff';
    if (!isStaff) return false;

    final soldBy = (orderStaffName ?? '').trim().toLowerCase();
    final me = (username ?? '').trim().toLowerCase();
    if (soldBy.isEmpty || me.isEmpty || soldBy != me) return false;
    if (soldAt == null) return false;

    final age = now.difference(soldAt);
    // A negative age means the device clock is behind the sale — refuse rather
    // than allow an unbounded correction window.
    if (age.isNegative) return false;
    return age <= window;
  }
}
