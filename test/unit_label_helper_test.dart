// test/unit_label_helper_test.dart
// A unit is stored on the drink and printed on invoices, so the dropdown has to
// translate the *label* while keeping the value canonical — and a unit a company
// typed itself must never be shown as a bare `unit_Foo` key. That last case was
// the live bug: the dropdown did `t('unit_' + unit)`, which silently falls back to
// the key for any custom unit.
import 'package:flutter_test/flutter_test.dart';
import 'package:drinks_calculator_fixed/utils/i18n.dart';
import 'package:drinks_calculator_fixed/utils/unit_label_helper.dart';

void main() {
  group('labelKey', () {
    test('every canonical unit maps to a unit_ key', () {
      for (final unit in kCanonicalUnits) {
        final key = UnitLabelHelper.labelKey(unit);
        expect(key, isNotNull, reason: '$unit has no label key');
        expect(key, 'unit_$unit');
      }
    });

    test('a company-added unit has no key', () {
      expect(UnitLabelHelper.labelKey('Sachet'), isNull);
      expect(UnitLabelHelper.labelKey(''), isNull);
    });
  });

  group('label', () {
    test('canonical unit is rendered through the translator', () {
      final shown = UnitLabelHelper.label('Bottle', (key) => 'FR:$key');
      expect(shown, 'FR:unit_Bottle');
    });

    test('custom unit is shown verbatim, never as a raw key', () {
      final shown = UnitLabelHelper.label('Sachet', (key) => 'FR:$key');
      expect(shown, 'Sachet');
      expect(shown.contains('unit_'), isFalse);
    });

    test('every canonical key really exists in the English map', () {
      for (final unit in kCanonicalUnits) {
        final key = UnitLabelHelper.labelKey(unit)!;
        // t() falls back to the key itself, so a missing entry is visible here.
        expect(t(key), isNot(key), reason: '$key is missing from _en');
      }
    });
  });
}
