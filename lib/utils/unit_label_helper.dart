// utils/unit_label_helper.dart
//
// A unit ("Bottle", "Can", "Crate") is DATA: it is stored on the drink and
// printed on invoices, and a company can also type a unit of its own (the form
// offers "New unit..."). So the UI shows a translated *label* while the stored
// value stays canonical English — and a custom unit is shown exactly as the
// operator typed it, never as a bare `unit_Foo` key.

/// The units the form offers, in order. Values are the stored ones.
const List<String> kCanonicalUnits = [
  'Bottle',
  'Can',
  'Glass',
  'Liter',
  'ml',
  'Piece',
  'Pack',
  'Crate',
];

/// Canonical unit → i18n key (both `_en` and `_fr` must carry it).
const Map<String, String> _unitLabelKeys = {
  'Bottle': 'unit_Bottle',
  'Can': 'unit_Can',
  'Glass': 'unit_Glass',
  'Liter': 'unit_Liter',
  'ml': 'unit_ml',
  'Piece': 'unit_Piece',
  'Pack': 'unit_Pack',
  'Crate': 'unit_Crate',
};

class UnitLabelHelper {
  /// The i18n key for a canonical unit, or `null` when the unit is one the
  /// company added itself.
  static String? labelKey(String unit) => _unitLabelKeys[unit];

  /// What to show in the UI: the translated label for a canonical unit, the
  /// raw value for a custom one. Pass `t` from `utils/i18n.dart` as
  /// [translate].
  static String label(String unit, String Function(String key) translate) {
    final key = labelKey(unit);
    return key == null ? unit : translate(key);
  }
}
