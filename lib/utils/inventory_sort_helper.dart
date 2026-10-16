// utils/inventory_sort_helper.dart
// The inventory sort menu: the label is translated, the stored value is not.
//
// The menu used to build its items from raw English strings and use the SAME string
// as the value, so translating the label would have silently changed what `_sortBy`
// holds and the sort switch (which compares against 'Name', 'Quantity (High)'…) would
// have stopped matching. The value stays the English identifier; only the label comes
// from the dictionary.
import 'i18n.dart';

class InventorySortLabels {
  InventorySortLabels._();

  /// Stored value -> i18n key. The order here is the order shown in the menu.
  static const Map<String, String> keyByValue = {
    'Name': 'invSortName',
    'Quantity (High)': 'invSortQtyHigh',
    'Quantity (Low)': 'invSortQtyLow',
    'Recently Restocked': 'invSortRecent',
  };

  /// The values the sort menu offers, in display order.
  static List<String> get values => keyByValue.keys.toList();

  /// Never returns a raw key: an unknown value falls back to the first label.
  static String label(String value) =>
      t(keyByValue[value] ?? keyByValue.values.first);
}
