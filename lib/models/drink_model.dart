// models/drink_model.dart
class Drink {
  final String id;
  final String name;
  final double price;
  final String category;
  final String imageUrl;
  final String barcode;
  final DateTime? createdAt;
  final String? userId;
  final int currentStock;
  final int minimumLevel;
  final String unit;          // e.g., 'Bottle', 'Can', 'Glass', 'Liter', 'Piece'
  final int unitsPerPack;      // units per case/pack (wholesale bulk)
  final double purchasePrice;

  /// What the unit measures: 'volume' | 'mass' | 'count'.
  final String unitKind;

  /// Batch dates (optional) — used to warn about expiring stock.
  final DateTime? productionDate;
  final DateTime? expiryDate;
  Drink({
    required this.id,
    required this.name,
    required this.price,
    this.category = 'Beer',
    required this.imageUrl,
    this.barcode = '',
    this.createdAt,
    this.userId,
    this.currentStock = 0,
    this.minimumLevel = 5,
    this.unit = 'Bottle',
    this.unitsPerPack = 1,
    this.purchasePrice = 0,
    this.unitKind = 'count',
    this.productionDate,
    this.expiryDate,
  });
  bool get isLowStock => currentStock <= minimumLevel;

  /// True when the batch has already expired.
  bool get isExpired {
    final exp = expiryDate;
    if (exp == null) return false;
    return DateTime.now().isAfter(DateTime(exp.year, exp.month, exp.day, 23, 59));
  }

  /// True when the batch expires within [days] days.
  bool get isExpiringSoon {
    final exp = expiryDate;
    if (exp == null || isExpired) return false;
    return DateTime(exp.year, exp.month, exp.day)
        .difference(DateTime.now())
        .inDays <= 30;
  }

  double get profitMargin => price - purchasePrice;
  double get profitPercentage => purchasePrice > 0 ? ((price - purchasePrice) / purchasePrice) * 100 : 0;
  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'price': price,
      'category': category,
      'image_url': imageUrl,
      'barcode': barcode,
      'created_at': createdAt?.toIso8601String(),
      'user_id': userId,
      'currentStock': currentStock,
      'minimumLevel': minimumLevel,
      'unit': unit,
      'unitsPerPack': unitsPerPack,
      'units_per_pack': unitsPerPack,
      'purchasePrice': purchasePrice,
      'unit_kind': unitKind,
      'production_date': productionDate?.toIso8601String().split('T').first,
      'expiry_date': expiryDate?.toIso8601String().split('T').first,
    };
  }

  // Create from JSON from Supabase
  factory Drink.fromJson(Map<String, dynamic> json) {
    return Drink(
      id: json['id']?.toString() ?? '',
      name: json['name']?.toString() ?? '',
      price: (json['price'] is int)
          ? (json['price'] as int).toDouble()
          : (json['price'] as num).toDouble(),
      category: json['category']?.toString() ?? 'Beer',
      imageUrl: json['image_url']?.toString() ??
          '', // Note: 'image_url' not 'imageUrl'
      barcode: json['barcode']?.toString() ?? '',
      createdAt: json['created_at'] != null
          ? DateTime.parse(json['created_at'])
          : null,
      userId: json['user_id']?.toString(),
      currentStock: json['currentStock'] ?? 0,
      minimumLevel: json['minimumLevel'] ?? 5,
      unit: json['unit']?.toString() ?? 'Bottle',
      unitsPerPack: json['unitsPerPack'] ?? json['units_per_pack'] ?? 1,
      purchasePrice: (json['purchasePrice'] ?? 0).toDouble(),
      unitKind: json['unit_kind']?.toString() ??
          json['unitKind']?.toString() ??
          'count',
      productionDate: _parseDate(json['production_date'] ?? json['productionDate']),
      expiryDate: _parseDate(json['expiry_date'] ?? json['expiryDate']),
    );
  }

  static DateTime? _parseDate(dynamic value) {
    if (value == null) return null;
    final raw = value.toString().trim();
    if (raw.isEmpty) return null;
    return DateTime.tryParse(raw);
  }

  // Copy with new values
  Drink copyWith({
    String? id,
    String? name,
    double? price,
    String? category,
    String? imageUrl,
    String? barcode,
    DateTime? createdAt,
    String? userId,
    int? currentStock,
    int? minimumLevel,
    String? unit,
    int? unitsPerPack,
    double? purchasePrice,
    String? unitKind,
    DateTime? productionDate,
    DateTime? expiryDate,
  }) {
    return Drink(
      id: id ?? this.id,
      name: name ?? this.name,
      price: price ?? this.price,
      category: category ?? this.category,
      imageUrl: imageUrl ?? this.imageUrl,
      barcode: barcode ?? this.barcode,
      createdAt: createdAt ?? this.createdAt,
      userId: userId ?? this.userId,
      currentStock: currentStock ?? this.currentStock,
      minimumLevel: minimumLevel ?? this.minimumLevel,
      unit: unit ?? this.unit,
      unitsPerPack: unitsPerPack ?? this.unitsPerPack,
      purchasePrice: purchasePrice ?? this.purchasePrice,
      unitKind: unitKind ?? this.unitKind,
      productionDate: productionDate ?? this.productionDate,
      expiryDate: expiryDate ?? this.expiryDate,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is Drink &&
          runtimeType == other.runtimeType &&
          id == other.id &&
          name == other.name;

  @override
  int get hashCode => id.hashCode ^ name.hashCode;

  @override
  String toString() {
    return 'Drink{id: $id, name: $name, price: $price, category: $category}';
  }
}