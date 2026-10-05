// utils/receipt_from_order.dart
// Turns a stored order (the drawer's Order History) back into what the receipt
// screen needs, so a past order can be reprinted or re-sent on WhatsApp.
//
// Pure — no widgets, no I/O — so the mapping is unit tested.
import '../models/drink_model.dart';
import '../models/order_model.dart';

class ReceiptFromOrder {
  ReceiptFromOrder._();

  /// The stored order as a drink list, **one entry per sold unit**, which is
  /// exactly what `ReceiptPrintScreen` regroups into the lines of the original
  /// receipt (same names, same quantities, same unit prices).
  static List<Drink> drinksFor(PurchaseHistory order) {
    final drinks = <Drink>[];
    for (var i = 0; i < order.items.length; i++) {
      final OrderItem item = order.items[i];
      final int quantity = item.quantity > 0 ? item.quantity : 1;
      for (var unit = 0; unit < quantity; unit++) {
        drinks.add(Drink(
          id: '${order.id}_${i}_$unit',
          name: item.drinkName,
          price: item.pricePerUnit,
          imageUrl: '',
        ));
      }
    }
    return drinks;
  }

  /// What to print as the customer. Orders recorded before customers were
  /// registered have no name — those fall back to [walkIn] ("Walk-in").
  static String customerLabel(PurchaseHistory order, String walkIn) {
    final String name = order.customerName.trim();
    return name.isEmpty ? walkIn : name;
  }

  /// A receipt with no lines is worse than no receipt at all: the UI says so
  /// instead of printing an empty one.
  static bool hasItems(PurchaseHistory order) => order.items.isNotEmpty;

  /// Units sold, for the "N items" line. A zero/negative quantity still counts
  /// as one sold unit, matching [drinksFor].
  static int unitCount(PurchaseHistory order) {
    var total = 0;
    for (final OrderItem item in order.items) {
      total += item.quantity > 0 ? item.quantity : 1;
    }
    return total;
  }
}
