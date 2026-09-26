// models/shift_model.dart
// One shift (a till session) and its Z-report.
//
// A shift belongs to the staff member who opened it; only one may be open per
// person. The report is computed by the backend from the orders inside the shift
// window and frozen onto the row when it closes, so a printed report never
// changes. The app-side mirror of those rules is utils/shift_helper.dart.
//
// Postgres NUMERIC columns come back as strings ("5000.00") through the backend,
// so every number is parsed tolerantly.

double? _asDouble(Object? value) {
  if (value == null) return null;
  if (value is num) return value.toDouble();
  return double.tryParse(value.toString().trim());
}

int _asInt(Object? value) {
  if (value == null) return 0;
  if (value is int) return value;
  return int.tryParse(value.toString().trim()) ?? 0;
}

Map<String, double> _asMoneyMap(Object? value) {
  final out = <String, double>{};
  if (value is Map) {
    value.forEach((key, amount) {
      final parsed = _asDouble(amount);
      if (parsed != null) out['$key'] = parsed;
    });
  }
  return out;
}

class Shift {
  final int id;
  final int staffUserId;
  final String staffName;

  /// open | closed
  final String status;
  final double openingFloat;
  final double cashPayouts;
  final double? cashCounted;
  final double? cashExpected;
  final double? variance;
  final int orderCount;
  final double totalSales;
  final double collected;
  final double onCredit;
  final Map<String, double> paymentBreakdown;
  final String notes;
  final DateTime? openedAt;
  final DateTime? closedAt;

  const Shift({
    required this.id,
    this.staffUserId = 0,
    this.staffName = '',
    this.status = 'open',
    this.openingFloat = 0,
    this.cashPayouts = 0,
    this.cashCounted,
    this.cashExpected,
    this.variance,
    this.orderCount = 0,
    this.totalSales = 0,
    this.collected = 0,
    this.onCredit = 0,
    this.paymentBreakdown = const {},
    this.notes = '',
    this.openedAt,
    this.closedAt,
  });

  bool get isOpen => status == 'open';

  factory Shift.fromJson(Map<String, dynamic> json) => Shift(
        id: _asInt(json['id']),
        staffUserId: _asInt(json['staff_user_id']),
        staffName: (json['staff_name'] ?? '').toString(),
        status: (json['status'] ?? 'open').toString().toLowerCase(),
        openingFloat: _asDouble(json['opening_float']) ?? 0,
        cashPayouts: _asDouble(json['cash_payouts']) ?? 0,
        cashCounted: _asDouble(json['cash_counted']),
        cashExpected: _asDouble(json['cash_expected']),
        variance: _asDouble(json['variance']),
        orderCount: _asInt(json['order_count']),
        totalSales: _asDouble(json['total_sales']) ?? 0,
        collected: _asDouble(json['collected']) ?? 0,
        onCredit: _asDouble(json['on_credit']) ?? 0,
        paymentBreakdown: _asMoneyMap(json['payment_breakdown']),
        notes: (json['notes'] ?? '').toString(),
        openedAt: DateTime.tryParse('${json['opened_at'] ?? ''}'),
        closedAt: DateTime.tryParse('${json['closed_at'] ?? ''}'),
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'staff_user_id': staffUserId,
        'staff_name': staffName,
        'status': status,
        'opening_float': openingFloat,
        'cash_payouts': cashPayouts,
        'cash_counted': cashCounted,
        'cash_expected': cashExpected,
        'variance': variance,
        'order_count': orderCount,
        'total_sales': totalSales,
        'collected': collected,
        'on_credit': onCredit,
        'payment_breakdown': paymentBreakdown,
        'notes': notes,
        'opened_at': openedAt?.toIso8601String(),
        'closed_at': closedAt?.toIso8601String(),
      };
}

/// The live numbers of a shift (`GET /shifts/:id/summary`) — or the frozen ones
/// of a closed shift.
class ShiftSummary {
  final double openingFloat;
  final double payouts;
  final double expectedCash;
  final double sales;
  final double collected;
  final double onCredit;
  final double? counted;
  final double? variance;
  final int orderCount;
  final Map<String, double> byMethod;

  const ShiftSummary({
    this.openingFloat = 0,
    this.payouts = 0,
    this.expectedCash = 0,
    this.sales = 0,
    this.collected = 0,
    this.onCredit = 0,
    this.counted,
    this.variance,
    this.orderCount = 0,
    this.byMethod = const {},
  });

  /// True when the drawer matches the expected cash (to the cent).
  bool get balanced => variance != null && variance!.abs() < 0.005;

  /// True when the till is short (money missing).
  bool get isShort => variance != null && variance! < -0.005;

  /// True when there is more cash than expected.
  bool get isOver => variance != null && variance! > 0.005;

  factory ShiftSummary.fromJson(Map<String, dynamic> json) => ShiftSummary(
        openingFloat: _asDouble(json['openingFloat']) ?? 0,
        payouts: _asDouble(json['payouts']) ?? 0,
        expectedCash: _asDouble(json['expectedCash']) ?? 0,
        sales: _asDouble(json['sales']) ?? 0,
        collected: _asDouble(json['collected']) ?? 0,
        onCredit: _asDouble(json['onCredit']) ?? 0,
        counted: _asDouble(json['counted']),
        variance: _asDouble(json['variance']),
        orderCount: _asInt(json['orderCount']),
        byMethod: _asMoneyMap(json['byMethod']),
      );
}