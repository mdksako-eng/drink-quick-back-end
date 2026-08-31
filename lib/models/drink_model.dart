// models/drink_model.dart
class Drink {
  final String id;
  final String name;
  final double price;
  final String category;
  final String imageUrl;
  final DateTime? createdAt;
  final String? userId;
  final int currentStock;
  final int minimumLevel;
  final String unit;          // e.g., 'Bottle', 'Can', 'Glass', 'Liter', 'Piece'
  final double purchasePrice;
  Drink({
    required this.id,
    required this.name,
    required this.price,
    this.category = 'Beer',
    required this.imageUrl,
    this.createdAt,
    this.userId,
    this.currentStock = 0,
    this.minimumLevel = 5,
    this.unit = 'Bottle',
    this.purchasePrice = 0,
  });
  bool get isLowStock => currentStock <= minimumLevel;
  double get profitMargin => price - purchasePrice;
  double get profitPercentage => purchasePrice > 0 ? ((price - purchasePrice) / purchasePrice) * 100 : 0;
  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'price': price,
      'category': category,
      'image_url': imageUrl,
      'created_at': createdAt?.toIso8601String(),
      'user_id': userId,
      'currentStock': currentStock,
      'minimumLevel': minimumLevel,
      'unit': unit,
      'purchasePrice': purchasePrice,
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
      createdAt: json['created_at'] != null
          ? DateTime.parse(json['created_at'])
          : null,
      userId: json['user_id']?.toString(),
      currentStock: json['currentStock'] ?? 0,
      minimumLevel: json['minimumLevel'] ?? 5,
      unit: json['unit']?.toString() ?? 'Bottle',
      purchasePrice: (json['purchasePrice'] ?? 0).toDouble(),
    );
  }

  // Copy with new values
  Drink copyWith({
    String? id,
    String? name,
    double? price,
    String? category,
    String? imageUrl,
    DateTime? createdAt,
    String? userId,
    int? currentStock,
    int? minimumLevel,
    String? unit,
    double? purchasePrice,
  }) {
    return Drink(
      id: id ?? this.id,
      name: name ?? this.name,
      price: price ?? this.price,
      category: category ?? this.category,
      imageUrl: imageUrl ?? this.imageUrl,
      createdAt: createdAt ?? this.createdAt,
      userId: userId ?? this.userId,
      currentStock: currentStock ?? this.currentStock,
      minimumLevel: minimumLevel ?? this.minimumLevel,
      unit: unit ?? this.unit,
      purchasePrice: purchasePrice ?? this.purchasePrice,
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