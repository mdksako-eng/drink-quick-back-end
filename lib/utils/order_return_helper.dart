// utils/order_return_helper.dart
// Turning "1 of 2 comes back" into a request the backend accepts, and reading the
// backend's answer back into something a dialog can draw.
//
// Pure, so the rules are unit tested instead of living inside the history widget.
//
// Two lessons from the re-invoice bug are baked in:
//   * the SERVER is the source of truth for what was sold and what is already
//     back — another device may have returned a unit — so the dialog draws the
//     server's lines and never does its own arithmetic, and
//   * a return is keyed on the drink id the invoice was stored with (the same id
//     the inventory row uses), so the stock move can find the shelf it belongs to.
//
// The ceiling lives on the server too (sold − already returned); everything here
// only avoids sending a request that would be refused as a whole.

/// One drink on the invoice, as far as a return is concerned.
class ReturnableLine {
  const ReturnableLine({
    required this.drinkId,
    required this.drinkName,
    required this.sold,
    required this.returned,
    required this.unitPrice,
  });

  final String drinkId;
  final String drinkName;

  /// Units on the invoice.
  final int sold;

  /// Units already given back (from the ledger, so it survives a restart).
  final int returned;

  /// What the customer paid per unit — the refund is that, not today's price.
  final double unitPrice;

  /// Never negative, whatever the ledger says.
  int get remaining => (sold - returned) < 0 ? 0 : sold - returned;

  bool get canReturn => remaining > 0;

  /// The refund for a chosen quantity, capped at what is still returnable.
  double amountFor(int quantity) {
    final q = clampQuantity(quantity);
    return unitPrice * q;
  }

  /// A quantity this line can actually be asked to give back.
  int clampQuantity(int quantity) {
    if (quantity < 0) return 0;
    return quantity > remaining ? remaining : quantity;
  }
}

class OrderReturnHelper {
  OrderReturnHelper._();

  static int _asInt(dynamic value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    return int.tryParse('${value ?? ''}') ?? 0;
  }

  static double _asDouble(dynamic value) {
    if (value is num) return value.toDouble();
    return double.tryParse('${value ?? ''}') ?? 0;
  }

  /// The endpoint's payload -> the lines a dialog can draw.
  ///
  /// Junk rows are dropped and impossible numbers are clamped, so a malformed or
  /// older payload can never offer a quantity the backend will refuse (a refusal
  /// cancels the whole return, not just that line).
  static List<ReturnableLine> linesFromApi(Map<String, dynamic> json) {
    final raw = json['lines'];
    if (raw is! List) return const [];
    final lines = <ReturnableLine>[];
    for (final entry in raw) {
      if (entry is! Map) continue;
      final line = Map<String, dynamic>.from(entry);
      final id = (line['drinkId'] ?? line['drink_id'] ?? '').toString();
      final name = (line['drinkName'] ?? line['drink_name'] ?? '').toString();
      if (id.isEmpty && name.isEmpty) continue;
      lines.add(ReturnableLine(
        drinkId: id,
        drinkName: name.isEmpty ? id : name,
        sold: _asInt(line['sold']).clamp(0, 1 << 20),
        returned: _asInt(line['returned']).clamp(0, 1 << 20),
        unitPrice: _asDouble(line['unitPrice'] ?? line['unit_price']),
      ));
    }
    return lines;
  }

  /// The chosen quantities -> the request body.
  ///
  /// Only lines that can give something back are sent, never zero, and never more
  /// than what remains: an over-ask is refused by the backend and would take the
  /// rest of the return down with it.
  static List<Map<String, dynamic>> requestItems(
    List<ReturnableLine> lines,
    Map<String, int> chosen,
  ) {
    final items = <Map<String, dynamic>>[];
    for (final line in lines) {
      final quantity = line.clampQuantity(chosen[line.drinkId] ?? 0);
      if (!line.canReturn || quantity <= 0) continue;
      items.add({
        'drink_id': line.drinkId,
        'drink_name': line.drinkName,
        'quantity': quantity,
      });
    }
    return items;
  }

  /// How many units are coming back.
  static int totalUnits(List<ReturnableLine> lines, Map<String, int> chosen) {
    var units = 0;
    for (final line in lines) {
      units += line.clampQuantity(chosen[line.drinkId] ?? 0);
    }
    return units;
  }

  /// The refund: what the customer paid for those units.
  static double totalAmount(List<ReturnableLine> lines, Map<String, int> chosen) {
    var total = 0.0;
    for (final line in lines) {
      total += line.unitPrice * line.clampQuantity(chosen[line.drinkId] ?? 0);
    }
    return total;
  }

  /// Is there anything at all left to give back on this invoice?
  static bool anyReturnable(List<ReturnableLine> lines) =>
      lines.any((line) => line.canReturn);
}
