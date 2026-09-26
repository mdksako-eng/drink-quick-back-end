// models/inventory_model.dart

/// Tolerant number read: Postgres NUMERIC columns reach the app as strings
/// ("800.00"), and `.toDouble()` on a string throws — which used to wipe the
/// whole inventory/ledger load (and with it the price history the variance
/// report needs).
double? _asDouble(Object? value) {
  if (value == null) return null;
  if (value is num) return value.toDouble();
  return double.tryParse(value.toString().trim());
}

class InventoryItem {
  final String id;
  final String drinkId;
  String drinkName;
  int quantity;
  int minStockLevel;
  DateTime lastRestocked;
  String category;
  String unit;
  double purchasePrice;
  int? companyId;
  
  InventoryItem({
    required this.id,
    required this.drinkId,
    required this.drinkName,
    required this.quantity,
    this.minStockLevel = 5,
    required this.lastRestocked,
    this.category = 'Beer',
    this.unit = 'Bottle',
    this.purchasePrice = 0,
    this.companyId,
  });

  bool get isLowStock => quantity <= minStockLevel;

  Map<String, dynamic> toJson() {
    final Map<String, dynamic> data = {};
    data['id'] = id;
    data['drinkId'] = drinkId;
    data['drinkName'] = drinkName;
    data['quantity'] = quantity;
    data['minStockLevel'] = minStockLevel;
    data['lastRestocked'] = lastRestocked.toIso8601String();
    data['category'] = category;
    data['unit'] = unit;
    data['purchasePrice'] = purchasePrice;
    
    if (companyId != null) {
      data['company_id'] = companyId;
    }
    
    return data;
  }

  factory InventoryItem.fromJson(Map<String, dynamic> json) {
    return InventoryItem(
      id: json['id']?.toString() ?? '',
      drinkId: json['drinkId']?.toString() ?? json['drink_id']?.toString() ?? '',
      drinkName: json['drinkName']?.toString() ?? json['drink_name']?.toString() ?? '',
      quantity: json['quantity'] ?? 0,
      minStockLevel: json['minStockLevel'] ?? json['min_stock_level'] ?? 5,
      lastRestocked: json['lastRestocked'] != null
          ? DateTime.parse(json['lastRestocked'])
          : (json['last_restocked'] != null 
              ? DateTime.parse(json['last_restocked']) 
              : DateTime.now()),
      category: json['category']?.toString() ?? 'Beer',
      unit: json['unit']?.toString() ?? 'Bottle',
      purchasePrice: _asDouble(json['purchasePrice'] ?? json['purchase_price']) ?? 0,
      companyId: json['company_id'],
    );
  }
}

class InventoryTransaction {
  final String id;
  final String drinkId;
  final String drinkName;
  final int quantity;
  final String type;
  final DateTime date;
  final String reason;
  final String? orderId;
  final String? performedBy;
  int? companyId;
  double? purchasePriceAtSale;
  double? sellingPriceAtSale;
  InventoryTransaction({
    required this.id,
    required this.drinkId,
    required this.drinkName,
    required this.quantity,
    required this.type,
    required this.date,
    required this.reason,
    this.orderId,
    this.performedBy,
    this.companyId,
    this.purchasePriceAtSale,   
    this.sellingPriceAtSale, 
  });

  bool get isIncoming => type == 'in';
  bool get isOutgoing => type == 'out';

  Map<String, dynamic> toJson() {
    final Map<String, dynamic> data = {};
    data['id'] = id;
    data['drinkId'] = drinkId;
    data['drinkName'] = drinkName;
    data['quantity'] = quantity;
    data['type'] = type;
    data['date'] = date.toIso8601String();
    data['reason'] = reason;
    data['orderId'] = orderId;
    data['performedBy'] = performedBy;
    
    if (companyId != null) {
      data['company_id'] = companyId;
    }
     if (purchasePriceAtSale != null) {
      data['purchasePriceAtSale'] = purchasePriceAtSale;
      data['purchase_price_at_sale'] = purchasePriceAtSale; // For Supabase
    }
    
    if (sellingPriceAtSale != null) {
      data['sellingPriceAtSale'] = sellingPriceAtSale;
      data['selling_price_at_sale'] = sellingPriceAtSale; // For Supabase
    }
    
    return data;
  }

  factory InventoryTransaction.fromJson(Map<String, dynamic> json) {
    return InventoryTransaction(
      id: json['id']?.toString() ?? '',
      drinkId: json['drinkId']?.toString() ?? json['drink_id']?.toString() ?? '',
      drinkName: json['drinkName']?.toString() ?? json['drink_name']?.toString() ?? '',
      quantity: json['quantity'] ?? 0,
      type: json['type']?.toString() ?? 'out',
      date: json['date'] != null ? DateTime.parse(json['date']) : DateTime.now(),
      reason: json['reason']?.toString() ?? 'sale',
      orderId: json['orderId']?.toString() ?? json['order_id']?.toString(),
      performedBy: json['performedBy']?.toString() ?? json['performed_by']?.toString(),
      companyId: json['company_id'],
      purchasePriceAtSale: _asDouble(
          json['purchasePriceAtSale'] ?? json['purchase_price_at_sale']),
      sellingPriceAtSale: _asDouble(
          json['sellingPriceAtSale'] ?? json['selling_price_at_sale']),
    );
  }
}

class InventoryReport {
  final DateTime startDate;
  final DateTime endDate;
  final List<InventoryItem> currentStock;
  final List<InventoryTransaction> transactions;
  final int totalItemsIn;
  final int totalItemsOut;
  final int lowStockCount;
  final Map<String, int> salesByCategory;
  final Map<String, int> wasteByItem;

  InventoryReport({
    required this.startDate,
    required this.endDate,
    required this.currentStock,
    required this.transactions,
    required this.totalItemsIn,
    required this.totalItemsOut,
    required this.lowStockCount,
    required this.salesByCategory,
    required this.wasteByItem,
  });

  int get netChange => totalItemsIn - totalItemsOut;
}