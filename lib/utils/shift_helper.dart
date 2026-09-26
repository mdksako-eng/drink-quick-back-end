// utils/shift_helper.dart
// Pure shift / cash-up rules for the Z-report, mirroring
// drinks-calculator-backend/utils/shiftMath.js so the screen can hide what the
// server would refuse anyway (the server stays the authority).
//
// A staff member opens a shift with the float in the drawer, closes it with the
// cash they counted, and the backend freezes the report onto the row.

class ShiftHelper {
  ShiftHelper._();

  /// Two decimals, so float noise never shows up as a variance.
  static double money(double value) => (value * 100).roundToDouble() / 100;

  /// What should be in the drawer: float + cash collected − payouts.
  static double expectedCash({
    required double openingFloat,
    required double collected,
    double payouts = 0,
  }) =>
      money(openingFloat + collected - payouts);

  /// Counted − expected: negative means the till is short.
  static double variance({
    required double counted,
    required double expectedCash,
  }) =>
      money(counted - expectedCash);

  /// True when the drawer matches the expected cash (to the cent).
  static bool balanced(double? variance) =>
      variance != null && variance.abs() < 0.005;

  static bool isShort(double? variance) => variance != null && variance < -0.005;

  static bool isOver(double? variance) => variance != null && variance > 0.005;

  /// Who may close a shift: the staff member who opened it, or any manager
  /// (an Administrator / the owner always may).
  static bool canClose({
    required String? role,
    required int? userId,
    required int? shiftStaffUserId,
    bool isOwner = false,
  }) {
    if (isOwner) return true;
    final r = (role ?? '').trim().toLowerCase();
    if (r == 'manager' || r == 'administrator' || r == 'admin') return true;
    if (userId == null || shiftStaffUserId == null) return false;
    return userId == shiftStaffUserId;
  }

  /// A float or a counted amount is a real, non-negative number.
  static bool isValidAmount(double? value) => value != null && value >= 0;

  /// i18n key for a shift status badge.
  static String statusKey(String? status) =>
      (status ?? '').trim().toLowerCase() == 'closed'
          ? 'shiftStatusClosed'
          : 'shiftStatusOpen';

  /// i18n key describing the variance: balanced, short or over.
  static String varianceKey(double? variance) {
    if (variance == null || balanced(variance)) return 'shiftBalanced';
    return variance < 0 ? 'shiftShort' : 'shiftOver';
  }

  /// "3h 25m" for a closed shift, or the elapsed time while it runs.
  static String durationLabel(DateTime? openedAt, {DateTime? closedAt}) {
    if (openedAt == null) return '-';
    final end = closedAt ?? DateTime.now();
    final minutes = end.difference(openedAt).inMinutes;
    if (minutes < 0) return '-';
    final hours = minutes ~/ 60;
    final rest = minutes % 60;
    if (hours <= 0) return '${rest}m';
    return '${hours}h ${rest}m';
  }

  /// The shift a new order belongs to: the one open on this device, if any.
  /// (The Z-report covers the shift window, so an order only counts once.)
  static bool coversOrder({
    required DateTime? openedAt,
    DateTime? closedAt,
    required DateTime? orderTime,
  }) {
    if (openedAt == null || orderTime == null) return false;
    if (orderTime.isBefore(openedAt)) return false;
    if (closedAt != null && orderTime.isAfter(closedAt)) return false;
    return true;
  }
}
