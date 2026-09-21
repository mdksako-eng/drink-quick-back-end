// test/phone_helper_test.dart
// Smart phone entry: the field must refuse more digits than the country uses,
// group them as the user types and reject impossible prefixes.
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:drinks_calculator_fixed/utils/phone_helper.dart';

void main() {
  group('country rules', () {
    test('Cameroon is 9 digits, Nigeria 10', () {
      expect(PhoneHelper.maxDigitsFor('CM'), 9);
      expect(PhoneHelper.maxDigitsFor('NG'), 10);
    });

    test('unknown country falls back to E.164 (15 digits)', () {
      expect(PhoneHelper.forCode('ZZ').code, 'X');
      expect(PhoneHelper.maxDigitsFor('ZZ'), 15);
    });

    test('dial codes resolve back to their country', () {
      expect(PhoneHelper.byDial('+237699000000')?.code, 'CM');
      expect(PhoneHelper.byDial('+2348012345678')?.code, 'NG');
      expect(PhoneHelper.byDial('+1'), isNull);
    });
  });

  group('formatting', () {
    test('a Cameroon number is grouped 1-2-2-2-2', () {
      expect(PhoneHelper.format('CM', '699123456'), '6 99 12 34 56');
    });

    test('a Nigeria number is grouped 3-3-4', () {
      expect(PhoneHelper.format('NG', '8031234567'), '803 123 4567');
    });

    test('extra digits are dropped, never shown', () {
      expect(PhoneHelper.format('CM', '6991234567890'), '6 99 12 34 56');
    });

    test('a leading trunk zero is removed', () {
      expect(PhoneHelper.format('CM', '0699123456'), '6 99 12 34 56');
    });

    test('toE164 rebuilds the international form', () {
      expect(PhoneHelper.toE164('CM', '6 99 12 34 56'), '+237699123456');
    });
  });

  group('validation', () {
    test('an incomplete Cameroon number is rejected until 9 digits', () {
      expect(PhoneHelper.validateErrorKey('CM', '69912345'), 'phoneWrongLength');
      expect(PhoneHelper.validateErrorKey('CM', '699123456'), '');
    });

    test('a Cameroon number must start with 6 (mobile) or 2/3/8 (landline)', () {
      expect(PhoneHelper.validateErrorKey('CM', '599123456'), 'phoneCmPrefix');
      expect(PhoneHelper.validateErrorKey('CM', '299123456'), '');
      expect(PhoneHelper.validateErrorKey('CM', '899123456'), '');
    });

    test('Nigeria requires 10 digits and a valid prefix', () {
      expect(PhoneHelper.validateErrorKey('NG', '803123456'), 'phoneWrongLength');
      expect(PhoneHelper.validateErrorKey('NG', '8031234567'), '');
      expect(PhoneHelper.validateErrorKey('NG', '2031234567'),
          'phoneInvalidPrefix');
    });

    test('required flag controls the empty case', () {
      expect(PhoneHelper.validateErrorKey('CM', ''), '');
      expect(PhoneHelper.validateErrorKey('CM', '', required: true),
          'phoneRequired');
    });

    test('international numbers accept 6-15 digits', () {
      expect(PhoneHelper.validateErrorKey('ZZ', '12345'), 'phoneInvalidLength');
      expect(PhoneHelper.validateErrorKey('ZZ', '1234567'), '');
    });

    test('isComplete only for a valid, non-empty number', () {
      expect(PhoneHelper.isComplete('CM', '6 99 12 34 56'), isTrue);
      expect(PhoneHelper.isComplete('CM', '6 99'), isFalse);
      expect(PhoneHelper.isComplete('CM', ''), isFalse);
    });
  });

  group('input formatter', () {
    TextEditingValue apply(
      List<TextInputFormatter> formatters,
      String typed, {
      String previous = '',
    }) {
      var value = TextEditingValue(
        text: previous,
        selection: TextSelection.collapsed(offset: previous.length),
      );
      for (final f in formatters) {
        value = f.formatEditUpdate(
          value,
          TextEditingValue(
            text: typed,
            selection: TextSelection.collapsed(offset: typed.length),
          ),
        );
      }
      return value;
    }

    test('typing past the country length is ignored', () {
      final result = apply(PhoneHelper.formattersFor('CM'), '699123456789');
      expect(result.text, '6 99 12 34 56');
    });

    test('the caret stays at the end while typing', () {
      final result = apply(PhoneHelper.formattersFor('CM'), '6991');
      expect(result.text, '6 99 1');
      expect(result.selection.baseOffset, result.text.length);
    });

    test('the international formatter allows up to 15 digits', () {
      final result =
          apply(PhoneHelper.internationalFormatters(), '123456789012345678');
      expect(PhoneHelper.digitsOnly(result.text).length, 15);
    });
  });
}
