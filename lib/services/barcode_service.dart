// services/barcode_service.dart
// Resolves a scanned barcode/QR code to a drink + its inventory item.
import '../models/drink_model.dart';
import '../models/inventory_model.dart';

class ScanMatch {
  final Drink drink;
  final InventoryItem? item;
  const ScanMatch({required this.drink, this.item});
}

class BarcodeService {
  BarcodeService._();

  /// Match a scanned raw string to a drink (by barcode, id or name),
  /// and return its inventory item when available.
  static ScanMatch? resolve(
    String raw, {
    required List<Drink> drinks,
    required List<InventoryItem> inventory,
  }) {
    final code = raw.trim();
    if (code.isEmpty) return null;
    final lower = code.toLowerCase();

    Drink? drink;
    for (final d in drinks) {
      if (d.barcode.isNotEmpty && d.barcode == code) {
        drink = d;
        break;
      }
    }
    if (drink == null) {
      for (final d in drinks) {
        if (d.id.isNotEmpty && d.id == code) {
          drink = d;
          break;
        }
      }
    }
    if (drink == null) {
      for (final d in drinks) {
        if (d.name.toLowerCase() == lower) {
          drink = d;
          break;
        }
      }
    }
    if (drink == null) {
      final partial =
          drinks.where((d) => d.name.toLowerCase().contains(lower)).toList();
      if (partial.length == 1) drink = partial.first;
    }
    if (drink == null) return null;

    InventoryItem? item;
    for (final i in inventory) {
      if (i.drinkId == drink.id || i.drinkName == drink.name) {
        item = i;
        break;
      }
    }
    return ScanMatch(drink: drink, item: item);
  }
}
