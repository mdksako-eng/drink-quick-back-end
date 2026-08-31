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

  PurchaseHistory({
    required this.id,
    required this.date,
    required this.items,
    required this.totalAmount,
    required this.amountPaid,
    this.isActive = true,
    this.customerName = '',
  }) : balance = amountPaid - totalAmount;

  Map<String, dynamic> toJson() => {
        'id': id,
        'date': date.toIso8601String(),
        'items': items.map((item) => item.toJson()).toList(),
        'totalAmount': totalAmount,
        'amountPaid': amountPaid,
        'balance': balance,
        'isActive': isActive,
        'customerName': customerName,
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
      );
}