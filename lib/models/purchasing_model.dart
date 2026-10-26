// models/purchasing_model.dart
// Buying stock: a supplier, a purchase order and its lines.
//
// WHY: the forecast recommends what to reorder; this is the document that turns
// that into an order and remembers what a supplier charges. Receiving the order
// is what puts the stock on the shelf at the price actually paid.
//
// Postgres NUMERIC columns come back as strings ("1000.00") through the backend,
// so every number is parsed tolerantly — the same rule as customer_model.dart.

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

class Supplier {
  final int id;
  final String name;
  final String phone;
  final String notes;
  final bool isActive;

  const Supplier({
    required this.id,
    required this.name,
    this.phone = '',
    this.notes = '',
    this.isActive = true,
  });

  factory Supplier.fromJson(Map<String, dynamic> json) => Supplier(
        id: _asInt(json['id']),
        name: (json['name'] ?? '').toString(),
        phone: (json['phone'] ?? '').toString(),
        notes: (json['notes'] ?? '').toString(),
        isActive: json['is_active'] == null
            ? true
            : json['is_active'] == true || json['is_active'] == 'true',
      );
}

/// One line: a whole number of units at the cost agreed with the supplier.
class PurchaseOrderLine {
  final int id;
  final String drinkId;
  final String drinkName;
  final int quantity;
  final double unitCost;

  const PurchaseOrderLine({
    required this.id,
    required this.drinkId,
    required this.drinkName,
    required this.quantity,
    this.unitCost = 0,
  });

  double get lineTotal => quantity * unitCost;

  factory PurchaseOrderLine.fromJson(Map<String, dynamic> json) =>
      PurchaseOrderLine(
        id: _asInt(json['id']),
        drinkId: (json['drink_id'] ?? '').toString(),
        drinkName: (json['drink_name'] ?? '').toString(),
        quantity: _asInt(json['quantity']),
        unitCost: _asDouble(json['unit_cost']) ?? 0,
      );
}

class PurchaseOrder {
  final int id;
  final String reference;
  final int? supplierId;

  /// draft | sent | received | cancelled
  final String status;
  final double totalAmount;
  final String notes;
  final String createdByName;
  final String receivedByName;
  final DateTime? createdAt;
  final DateTime? sentAt;
  final DateTime? receivedAt;
  final List<PurchaseOrderLine> lines;

  const PurchaseOrder({
    required this.id,
    required this.reference,
    this.supplierId,
    this.status = 'draft',
    this.totalAmount = 0,
    this.notes = '',
    this.createdByName = '',
    this.receivedByName = '',
    this.createdAt,
    this.sentAt,
    this.receivedAt,
    this.lines = const [],
  });

  bool get isDraft => status == 'draft';
  bool get isSent => status == 'sent';
  bool get isReceived => status == 'received';
  bool get isCancelled => status == 'cancelled';

  /// Only a draft or a sent order can still be acted on.
  bool get isOpen => isDraft || isSent;

  int get totalUnits =>
      lines.fold(0, (sum, line) => sum + line.quantity);

  factory PurchaseOrder.fromJson(Map<String, dynamic> json) => PurchaseOrder(
        id: _asInt(json['id']),
        reference: (json['reference'] ?? '').toString(),
        supplierId: json['supplier_id'] == null
            ? null
            : _asInt(json['supplier_id']),
        status: (json['status'] ?? 'draft').toString().toLowerCase(),
        totalAmount: _asDouble(json['total_amount']) ?? 0,
        notes: (json['notes'] ?? '').toString(),
        createdByName: (json['created_by_name'] ?? '').toString(),
        receivedByName: (json['received_by_name'] ?? '').toString(),
        createdAt: DateTime.tryParse('${json['created_at'] ?? ''}'),
        sentAt: DateTime.tryParse('${json['sent_at'] ?? ''}'),
        receivedAt: DateTime.tryParse('${json['received_at'] ?? ''}'),
        lines: ((json['lines'] as List?) ?? [])
            .whereType<Map>()
            .map((row) =>
                PurchaseOrderLine.fromJson(Map<String, dynamic>.from(row)))
            .toList(),
      );
}
