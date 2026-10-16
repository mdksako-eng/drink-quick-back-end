// test/inventory_sort_helper_test.dart
// The sort menu shows translated labels while the stored value stays the English
// identifier the sort switch compares against. The regression this guards: the menu
// used to use the same English string as both label and value, so translating the
// label would have silently changed what `_sortBy` holds and broken the sorting.
import 'package:flutter_test/flutter_test.dart';
import 'package:drinks_calculator_fixed/utils/i18n.dart';
import 'package:drinks_calculator_fixed/utils/inventory_sort_helper.dart';

void main() {
  test('the values are the identifiers the screen switches on', () {
    expect(InventorySortLabels.values, [
      'Name',
      'Quantity (High)',
      'Quantity (Low)',
      'Recently Restocked',
    ]);
  });

  test('every value has a label that exists in both maps', () {
    for (final value in InventorySortLabels.values) {
      final label = InventorySortLabels.label(value);
      expect(label.trim(), isNotEmpty);
      // t() falls back to the key itself, so a missing translation would show the key.
      expect(label, isNot(contains('invSort')));
    }
    // Proof that a lookup happened at all: the punctuation differs from the value.
    expect(InventorySortLabels.label('Quantity (High)'), 'Quantity (high to low)');
    expect(InventorySortLabels.label('Recently Restocked'), 'Recently restocked');
  });

  test('an unknown value falls back to a label rather than showing a key', () {
    expect(InventorySortLabels.label('Something New'), t('invSortName'));
    expect(InventorySortLabels.label(''), t('invSortName'));
  });
}
