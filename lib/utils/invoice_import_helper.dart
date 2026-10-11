// utils/invoice_import_helper.dart
// Turning a past invoice back into a cart ("Edit & Re-invoice").
//
// Pure, so the rule is unit tested instead of living inside the history widget.
//
// The trap this closes: the cart, the stock commit and the server all key on the
// drink id, so a line rebuilt with a made-up id ("import_<timestamp>_…") made the
// whole re-invoice fail at the stock step — "not enough stock" with a full shelf —
// because no inventory row carried that id. Every line must be rebuilt from the
// REAL catalogue drink; only the price stays what the customer was originally
// charged.
import '../models/drink_model.dart';
import '../models/order_model.dart';

/// What an invoice becomes in the cart: one entry per unit sold, or the name of
/// the first line whose drink is no longer in the catalogue.
class InvoiceImportPlan {
  const InvoiceImportPlan({required this.drinks, this.missingDrink});

  /// One entry per unit, each carrying the real catalogue drink id.
  final List<Drink> drinks;

  /// Set when a line could not be resolved: the caller must refuse the import
  /// rather than invent a line (which the stock commit can never deduct) or drop
  /// it silently (which would under-bill the customer).
  final String? missingDrink;

  bool get canImport => missingDrink == null && drinks.isNotEmpty;
}

class InvoiceImportHelper {
  InvoiceImportHelper._();

  /// The catalogue drink an invoice line refers to.
  ///
  /// Invoices store the name the drink had when it was sold, so the match is on
  /// the trimmed, lower-cased name — never on the id or the price, which change.
  static Drink? findCatalogDrink(String name, List<Drink> catalog) {
    final wanted = name.trim().toLowerCase();
    if (wanted.isEmpty) return null;
    for (final drink in catalog) {
      if (drink.name.trim().toLowerCase() == wanted) return drink;
    }
    return null;
  }

  /// Expands an invoice into cart entries: one per unit (the cart counts entries,
  /// not quantities), each with the catalogue identity and stock metadata, priced
  /// at what the invoice charged — falling back to the catalogue price when the
  /// invoice carries none.
  static InvoiceImportPlan plan({
    required List<OrderItem> items,
    required List<Drink> catalog,
  }) {
    final drinks = <Drink>[];
    for (final item in items) {
      final match = findCatalogDrink(item.drinkName, catalog);
      if (match == null) {
        return InvoiceImportPlan(drinks: const [], missingDrink: item.drinkName);
      }
      final priced = item.pricePerUnit > 0
          ? match.copyWith(price: item.pricePerUnit)
          : match;
      final quantity = item.quantity < 1 ? 1 : item.quantity;
      for (var i = 0; i < quantity; i++) {
        drinks.add(priced);
      }
    }
    return InvoiceImportPlan(drinks: drinks);
  }
}
