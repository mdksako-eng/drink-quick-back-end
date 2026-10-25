// models/container_model.dart
// Returnable containers (crates and bottles) and one movement of them.
//
// WHY: the credit ledger answers "who owes me money"; this answers "who owes me
// containers" — a crate sitting in a customer's yard is money standing still.
// The balance is always SUMMED from the movements (see
// utils/container_ledger_helper.dart), never stored, so it can never disagree
// with its own history.
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

/// One kind of container the shop hands out: a crate, a bottle, a pallet…
class ContainerType {
  final int id;
  final String name;

  /// What one container is worth as a deposit (0 when the shop charges none).
  /// Informational only: containers are goods, not cash.
  final double depositValue;
  final bool isActive;

  const ContainerType({
    required this.id,
    required this.name,
    this.depositValue = 0,
    this.isActive = true,
  });

  factory ContainerType.fromJson(Map<String, dynamic> json) => ContainerType(
        id: _asInt(json['id']),
        name: (json['name'] ?? '').toString(),
        depositValue: _asDouble(json['deposit_value']) ?? 0,
        isActive: json['is_active'] == null
            ? true
            : json['is_active'] == true || json['is_active'] == 'true',
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'deposit_value': depositValue,
        'is_active': isActive,
      };
}

/// One movement: a container went out, came back, or was written off.
class ContainerMovement {
  final int id;
  final int customerId;
  final int containerTypeId;

  /// out | back | writeoff
  final String kind;
  final int quantity;
  final String reason;
  final String performedByName;
  final DateTime? createdAt;

  const ContainerMovement({
    required this.id,
    required this.customerId,
    required this.containerTypeId,
    required this.kind,
    required this.quantity,
    this.reason = '',
    this.performedByName = '',
    this.createdAt,
  });

  bool get isOut => kind == 'out';
  bool get isBack => kind == 'back';
  bool get isWriteOff => kind == 'writeoff';

  factory ContainerMovement.fromJson(Map<String, dynamic> json) =>
      ContainerMovement(
        id: _asInt(json['id']),
        customerId: _asInt(json['customer_id']),
        containerTypeId: _asInt(json['container_type_id']),
        kind: (json['kind'] ?? 'out').toString().toLowerCase(),
        quantity: _asInt(json['quantity']),
        reason: (json['reason'] ?? '').toString(),
        performedByName: (json['performed_by_name'] ?? '').toString(),
        createdAt: DateTime.tryParse('${json['created_at'] ?? ''}'),
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'customer_id': customerId,
        'container_type_id': containerTypeId,
        'kind': kind,
        'quantity': quantity,
        'reason': reason,
        'performed_by_name': performedByName,
        'created_at': createdAt?.toIso8601String(),
      };
}
