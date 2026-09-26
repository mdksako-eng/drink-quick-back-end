// models/customer_model.dart
// A customer account ("customer number") and one line of its credit ledger.
//
// WHO DECIDES WHAT: STAFF enrol a customer, a MANAGER holds the final say on
// who is approved. Only an approved account may hold credit — the rules are in
// utils/customer_ledger_helper.dart (a mirror of the backend's
// drinks-calculator-backend/utils/customerApproval.js).
//
// Postgres NUMERIC columns come back as strings ("5000.00") through the
// backend, so every number is parsed tolerantly.

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

class Customer {
  final int id;
  final String customerNumber;
  final String name;
  final String phone;

  /// pending | approved | rejected | blocked
  final String status;
  final double creditLimit;
  final String notes;
  final DateTime? createdAt;

  const Customer({
    required this.id,
    required this.customerNumber,
    required this.name,
    this.phone = '',
    this.status = 'pending',
    this.creditLimit = 0,
    this.notes = '',
    this.createdAt,
  });

  factory Customer.fromJson(Map<String, dynamic> json) => Customer(
        id: _asInt(json['id']),
        customerNumber: (json['customer_number'] ?? '').toString(),
        name: (json['name'] ?? '').toString(),
        phone: (json['phone'] ?? '').toString(),
        status: (json['status'] ?? 'pending').toString().toLowerCase(),
        creditLimit: _asDouble(json['credit_limit']) ?? 0,
        notes: (json['notes'] ?? '').toString(),
        createdAt: DateTime.tryParse('${json['created_at'] ?? ''}'),
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'customer_number': customerNumber,
        'name': name,
        'phone': phone,
        'status': status,
        'credit_limit': creditLimit,
        'notes': notes,
        'created_at': createdAt?.toIso8601String(),
      };
}

/// One line of a customer's tab: a 'charge' (credit given) or a 'payment'.
class CustomerLedgerEntry {
  final int id;
  final int customerId;

  /// charge | payment
  final String kind;
  final double amount;
  final String reason;
  final String method;
  final String performedByName;
  final DateTime? createdAt;

  const CustomerLedgerEntry({
    required this.id,
    required this.customerId,
    required this.kind,
    required this.amount,
    this.reason = '',
    this.method = '',
    this.performedByName = '',
    this.createdAt,
  });

  bool get isPayment => kind == 'payment';

  factory CustomerLedgerEntry.fromJson(Map<String, dynamic> json) =>
      CustomerLedgerEntry(
        id: _asInt(json['id']),
        customerId: _asInt(json['customer_id']),
        kind: (json['kind'] ?? 'charge').toString().toLowerCase(),
        amount: _asDouble(json['amount']) ?? 0,
        reason: (json['reason'] ?? '').toString(),
        method: (json['method'] ?? '').toString(),
        performedByName: (json['performed_by_name'] ?? '').toString(),
        createdAt: DateTime.tryParse('${json['created_at'] ?? ''}'),
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'customer_id': customerId,
        'kind': kind,
        'amount': amount,
        'reason': reason,
        'method': method,
        'performed_by_name': performedByName,
        'created_at': createdAt?.toIso8601String(),
      };
}