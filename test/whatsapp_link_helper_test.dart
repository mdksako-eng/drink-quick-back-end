// test/whatsapp_link_helper_test.dart
// Regression tests for the WhatsApp payment-link builder.
//
// wa.me only accepts the international form (country code + national number,
// digits only, no "+" and no leading zero). A Cameroonian number typed the way
// people actually write it — 6XX XX XX XX — produces a link that fails SILENTLY,
// so the conversion has to be pinned down by tests.
import 'package:flutter_test/flutter_test.dart';

import 'package:drinks_calculator_fixed/utils/whatsapp_link_helper.dart';

const _message = 'Pay Frs 6,000 for your drinks: https://pay.example/x';

/// The `text=` part, decoded, so the assertions do not depend on which
/// characters Uri.encodeComponent happens to escape.
String _decodedText(String link) =>
    Uri.decodeComponent(link.split('?text=').last);

void main() {
  group('buildWhatsAppPaymentLink normalises the number', () {
    test('local format with spaces gets the country code', () {
      final link = buildWhatsAppPaymentLink(
          number: '677 123 456', message: _message);
      expect(link, isNotNull);
      expect(link!.startsWith('https://wa.me/237677123456?text='), isTrue);
    });

    test('a leading zero is dropped', () {
      final link = buildWhatsAppPaymentLink(
          number: '0677 123 456', message: _message);
      expect(link, isNotNull);
      expect(link!.startsWith('https://wa.me/237677123456?text='), isTrue);
    });

    test('an already-international number is left alone', () {
      final link = buildWhatsAppPaymentLink(
          number: '237677123456', message: _message);
      expect(link, isNotNull);
      expect(link!.startsWith('https://wa.me/237677123456?text='), isTrue);
    });

    test('a + and separators are stripped from the international form', () {
      final link = buildWhatsAppPaymentLink(
          number: '+237 677-123-456', message: _message);
      expect(link, isNotNull);
      expect(link!.startsWith('https://wa.me/237677123456?text='), isTrue);
    });

    test('another country code is honoured', () {
      final link = buildWhatsAppPaymentLink(
          number: '612 345 678', message: _message, dialCode: '33');
      expect(link, isNotNull);
      expect(link!.startsWith('https://wa.me/33612345678?text='), isTrue);
    });
  });

  group('buildWhatsAppPaymentLink refuses what cannot work', () {
    test('an empty number is null, not a broken link', () {
      expect(buildWhatsAppPaymentLink(number: '', message: _message), isNull);
    });

    test('letters and punctuation with no digits are null', () {
      expect(
          buildWhatsAppPaymentLink(number: 'not a number', message: _message),
          isNull);
    });

    test('a number that is too short is null', () {
      expect(buildWhatsAppPaymentLink(number: '12345', message: _message),
          isNull);
    });
  });

  group('the message survives the trip', () {
    test('it is URL-encoded and decodes back unchanged', () {
      final link = buildWhatsAppPaymentLink(
          number: '677123456', message: _message);
      expect(link, isNotNull);
      expect(_decodedText(link!), _message);
      // The raw link must not carry characters that would cut the query short.
      expect(link.contains(' '), isFalse);
      expect(link.split('?text=').last.contains('&'), isFalse);
    });
  });
}
