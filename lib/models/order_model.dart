// models/order_model.dart
class OrderItem {
  String drinkName;
  int quantity;
  double pricePerUnit;
  double totalPrice;

  OrderItem({
    required this.drinkName,
    required this.quantity,
    required this.pricePerUnit,
  }) : totalPrice = quantity * pricePerUnit;

  Map<String, dynamic> toJson() => {
        'drinkName': drinkName,
        'quantity': quantity,
        'pricePerUnit': pricePerUnit,
        'totalPrice': totalPrice,
      };

  factory OrderItem.fromJson(Map<String, dynamic> json) => OrderItem(
        drinkName: json['drinkName'],
        quantity: json['quantity'],
        pricePerUnit: json['pricePerUnit'].toDouble(),
      );
}

class PurchaseHistory {
  String id;
  DateTime date;
  List<OrderItem> items;
  double totalAmount;
  double amountPaid;
  double balance;
  bool isActive;
  String customerName;

  /// Who rang the sale. Kept so a staff member can be allowed to correct their own
  /// sale (and only theirs) within the window — mirrors utils/order_correction_helper.
  String staffName;

  /// Set when a manager corrected this order: the trace stays with the order so
  /// the shift report and this list can explain why a sale disappeared.
  DateTime? voidedAt;
  String voidReason;
  String voidedByName;

  PurchaseHistory({
    required this.id,
    required this.date,
    required this.items,
    required this.totalAmount,
    required this.amountPaid,
    this.isActive = true,
    this.customerName = '',
    this.staffName = '',
    this.voidedAt,
    this.voidReason = '',
    this.voidedByName = '',
  }) : balance = amountPaid - totalAmount;

  bool get isVoided => voidedAt != null;

  Map<String, dynamic> toJson() => {
        'id': id,
        'date': date.toIso8601String(),
        'items': items.map((item) => item.toJson()).toList(),
        'totalAmount': totalAmount,
        'amountPaid': amountPaid,
        'balance': balance,
        'isActive': isActive,
        'customerName': customerName,
        'staffName': staffName,
        'voidedAt': voidedAt?.toIso8601String(),
        'voidReason': voidReason,
        'voidedByName': voidedByName,
      };

  factory PurchaseHistory.fromJson(Map<String, dynamic> json) => PurchaseHistory(
        id: json['id'],
        date: DateTime.parse(json['date']),
        items: (json['items'] as List)
            .map((item) => OrderItem.fromJson(item))
            .toList(),
        totalAmount: json['totalAmount'].toDouble(),
        amountPaid: json['amountPaid'].toDouble(),
        isActive: json['isActive'] ?? true,
        customerName: json['customerName'] ?? '',
        staffName: (json['staffName'] ?? '').toString(),
        voidedAt: DateTime.tryParse('${json['voidedAt'] ?? ''}'),
        voidReason: (json['voidReason'] ?? '').toString(),
        voidedByName: (json['voidedByName'] ?? '').toString(),
      );
}