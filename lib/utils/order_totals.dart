// utils/order_totals.dart
//
// 🔢 How many drinks did a sale actually move?
//
// The cart merges a repeated drink into ONE line carrying a quantity (a crate sale
// is a single line of 24, see the calculator's `quantity: entry.value`), so a cart
// line count is not a drink count. Notifications reported "1 item" for a sale of 24
// crates because they used `items.length`.
//
// Pure so it can be tested without a provider or a widget.

/// Total units in a cart / order, i.e. the sum of every line's quantity.
///
/// A line with a quantity of 0 or less contributes nothing, and a line whose
/// quantity was never set (defensive: a hand-built model) counts as one unit
/// instead of silently vanishing from the total.
int totalUnits(Iterable<dynamic> items) {
  var total = 0;
  for (final item in items) {
    if (item == null) continue;
    final dynamic quantity = _quantityOf(item);
    if (quantity is int) {
      total += quantity > 0 ? quantity : 0;
    } else if (quantity is num) {
      final asInt = quantity.toInt();
      total += asInt > 0 ? asInt : 0;
    } else {
      // No usable quantity → treat the line as a single unit.
      total += 1;
    }
  }
  return total;
}

dynamic _quantityOf(dynamic item) {
  try {
    return item.quantity;
  } catch (_) {
    return null;
  }
}
