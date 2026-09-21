// utils/phone_helper.dart
// Smart phone-number entry: keeps the field to the number of digits the selected
// country actually uses, groups them as you type and validates the prefix.
//
// Before this, the signup/settings fields accepted unlimited digits and only
// complained after the user pressed Save.
import 'package:flutter/services.dart';

/// One country's dialling rules.
class PhoneCountry {
  const PhoneCountry({
    required this.code,
    required this.name,
    required this.dial,
    required this.flag,
    required this.groups,
    required this.mobilePrefixes,
    this.landlinePrefixes = const [],
  });

  /// ISO code, e.g. `CM`.
  final String code;
  final String name;
  final String dial;
  final String flag;

  /// Digit group sizes, e.g. `[1, 2, 2, 2, 2]` renders `6 99 99 99 99`.
  final List<int> groups;

  /// Valid leading digits for a mobile number.
  final List<String> mobilePrefixes;

  /// Valid leading digits for a landline number.
  final List<String> landlinePrefixes;

  /// Total digits after the dial code.
  int get nationalLength => groups.fold(0, (sum, g) => sum + g);

  /// Human mask, e.g. `6XX XXX XXX`.
  String get mask {
    final buffer = StringBuffer();
    for (final group in groups) {
      if (buffer.isNotEmpty) buffer.write(' ');
      buffer.write('9' * group);
    }
    return buffer.toString();
  }
}

class PhoneHelper {
  PhoneHelper._();

  static const List<PhoneCountry> countries = [
    PhoneCountry(
      code: 'CM',
      name: 'Cameroon',
      dial: '+237',
      flag: '🇨🇲',
      groups: [1, 2, 2, 2, 2], // 9 digits
      mobilePrefixes: ['6'],
      landlinePrefixes: ['2', '3', '8'],
    ),
    PhoneCountry(
      code: 'NG',
      name: 'Nigeria',
      dial: '+234',
      flag: '🇳🇬',
      groups: [3, 3, 4], // 10 digits
      mobilePrefixes: ['7', '8', '9'],
      landlinePrefixes: ['1'],
    ),
  ];

  /// Fallback used when the country is unknown: international numbers may be up
  /// to 15 digits (E.164), grouped in 3s.
  static const PhoneCountry international = PhoneCountry(
    code: 'X',
    name: 'International',
    dial: '+',
    flag: '🌍',
    groups: [3, 3, 3, 3, 3],
    mobilePrefixes: [],
    landlinePrefixes: [],
  );

  static PhoneCountry forCode(String? code) => countries.firstWhere(
        (c) => c.code == (code ?? '').toUpperCase(),
        orElse: () => international,
      );

  /// Country that owns [dial] (e.g. `+237` → Cameroon), longest match first.
  static PhoneCountry? byDial(String dial) {
    final digits = digitsOnly(dial);
    PhoneCountry? best;
    for (final country in countries) {
      final cd = digitsOnly(country.dial);
      if (digits.startsWith(cd) &&
          (best == null || cd.length > digitsOnly(best.dial).length)) {
        best = country;
      }
    }
    return best;
  }

  /// Digits only — users type spaces, dashes or a leading zero out of habit.
  static String digitsOnly(String? input) =>
      (input ?? '').replaceAll(RegExp(r'[^\d]'), '');

  /// Drops a single leading `0` (national trunk prefix) when the user typed one.
  static String stripLeadingZero(String digits) =>
      digits.length > 1 && digits.startsWith('0')
          ? digits.substring(1)
          : digits;

  static int maxDigitsFor(String? code) => forCode(code).nationalLength;

  /// Formats [input] for display (and storage in the field), cutting anything
  /// past the country's digit count so the user simply cannot type too many.
  static String format(String? code, String? input) {
    final country = forCode(code);
    var digits = stripLeadingZero(digitsOnly(input));
    if (digits.length > country.nationalLength) {
      digits = digits.substring(0, country.nationalLength);
    }
    return _group(digits, country.groups);
  }

  /// e.g. `+237699123456`
  static String toE164(String? code, String? input) {
    final country = forCode(code);
    final digits = stripLeadingZero(digitsOnly(input));
    if (digits.isEmpty) return '';
    return '${country.dial}$digits';
  }

  /// [return] An i18n key for the error (`''` = valid). Callers translate it, so
  /// the helper stays free of UI strings.
  static String validateErrorKey(
    String? code,
    String? input, {
    bool required = false,
  }) {
    final digits = stripLeadingZero(digitsOnly(input));
    if (digits.isEmpty) return required ? 'phoneRequired' : '';
    final country = forCode(code);
    if (country.code == international.code) {
      if (digits.length < 6 || digits.length > 15) return 'phoneInvalidLength';
      return '';
    }
    if (digits.length != country.nationalLength) return 'phoneWrongLength';
    final prefixes = [...country.mobilePrefixes, ...country.landlinePrefixes];
    if (prefixes.isNotEmpty && !prefixes.contains(digits[0])) {
      return country.code == 'CM' ? 'phoneCmPrefix' : 'phoneInvalidPrefix';
    }
    return '';
  }

  /// True once the entered number is complete and valid.
  static bool isComplete(String? code, String? input) =>
      validateErrorKey(code, input) == '' && digitsOnly(input).isNotEmpty;

  /// Input formatter that caps the length and groups as the user types.
  static List<TextInputFormatter> formattersFor(String? code) => [
        _PhoneInputFormatter(forCode(code)),
      ];

  /// Formatter for fields where the country is unknown (merchant/operator
  /// numbers): E.164 length, grouped in 3s.
  static List<TextInputFormatter> internationalFormatters() => [
        _PhoneInputFormatter(international),
      ];

  static String _group(String digits, List<int> groups) {
    final buffer = StringBuffer();
    var index = 0;
    for (final size in groups) {
      if (index >= digits.length) break;
      final end = (index + size).clamp(0, digits.length);
      if (buffer.isNotEmpty) buffer.write(' ');
      buffer.write(digits.substring(index, end));
      index = end;
    }
    if (index < digits.length) buffer.write(digits.substring(index));
    return buffer.toString();
  }
}

/// Applies [PhoneHelper.format] on every keystroke, keeping the caret at the end
/// (which is what users expect when typing a phone number) and refusing extra
/// digits instead of showing them and failing validation later.
class _PhoneInputFormatter extends TextInputFormatter {
  _PhoneInputFormatter(this.country);

  final PhoneCountry country;

  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    final digits =
        PhoneHelper.stripLeadingZero(PhoneHelper.digitsOnly(newValue.text));
    final capped = digits.length > country.nationalLength
        ? digits.substring(0, country.nationalLength)
        : digits;

    final formatted = PhoneHelper._group(capped, country.groups);
    return TextEditingValue(
      text: formatted,
      selection: TextSelection.collapsed(offset: formatted.length),
    );
  }
}
