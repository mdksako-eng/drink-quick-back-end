// test/color_helper_test.dart
// The primary colour is read from settings on every startup. A corrupted value used
// to throw inside build() and kill the screen; these tests pin the "never throws"
// promise and the accepted formats.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:drinks_calculator_fixed/utils/color_helper.dart';

void main() {
  group('parseHexColor — accepted formats', () {
    test('#RRGGBB', () {
      expect(parseHexColor('#667EEA'), const Color(0xFF667EEA));
    });

    test('RRGGBB without the hash', () {
      expect(parseHexColor('667EEA'), const Color(0xFF667EEA));
    });

    test('#RGB shorthand expands', () {
      expect(parseHexColor('#abc'), const Color(0xFFAABBCC));
    });

    test('#AARRGGBB keeps its alpha', () {
      expect(parseHexColor('#80FF0000'), const Color(0x80FF0000));
    });

    test('0xAARRGGBB', () {
      expect(parseHexColor('0xFF00FF00'), const Color(0xFF00FF00));
    });

    test('lowercase and surrounding spaces are fine', () {
      expect(parseHexColor('  #667eea  '), const Color(0xFF667EEA));
    });
  });

  group('parseHexColor — never throws', () {
    const fallback = kFallbackPrimaryColor;

    test('null, empty and whitespace fall back', () {
      expect(parseHexColor(null), fallback);
      expect(parseHexColor(''), fallback);
      expect(parseHexColor('   '), fallback);
    });

    test('garbage and wrong lengths fall back', () {
      expect(parseHexColor('not-a-colour'), fallback);
      expect(parseHexColor('#12345'), fallback);
      expect(parseHexColor('#1234567'), fallback);
      expect(parseHexColor('#GGGGGG'), fallback);
      expect(parseHexColor('0x'), fallback);
      expect(parseHexColor('#'), fallback);
    });

    test('a custom fallback is honoured', () {
      expect(parseHexColor('nope', fallback: Colors.black), Colors.black);
    });
  });
}
