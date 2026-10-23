// test/payments_status_test.dart
// The subscription screen warns "test mode" while real money cannot move. That
// warning used to come from the Notch Pay health payload — a rail that was removed —
// so it showed TEST forever, even while CamerPay was charging real cards. These
// tests pin the CamerPay shape and, most importantly, that a missing `mode` field
// no longer forces TEST.
import 'package:flutter_test/flutter_test.dart';
import 'package:drinks_calculator_fixed/services/payments_status_service.dart';

void main() {
  group('PaymentsStatus.fromJson (CamerPay payload)', () {
    test('an account declared live reports LIVE', () {
      final status = PaymentsStatus.fromJson(const {
        'provider': 'campay',
        'configured': true,
        'accountDeclaredLive': true,
        'liveReady': true,
        'hint': 'CamerPay account declared live',
      });
      expect(status.isLive, isTrue);
      expect(status.shortLabel, 'LIVE');
      expect(status.providerConfigured, isTrue);
    });

    test('configured but not declared live is still TEST', () {
      final status = PaymentsStatus.fromJson(const {
        'provider': 'campay',
        'configured': true,
        'accountDeclaredLive': false,
        'liveReady': false,
      });
      expect(status.isLive, isFalse);
      expect(status.shortLabel, 'TEST');
      expect(status.providerConfigured, isTrue);
    });

    test('nothing configured is TEST', () {
      final status = PaymentsStatus.fromJson(const {
        'configured': false,
        'liveReady': false,
      });
      expect(status.isLive, isFalse);
      expect(status.providerConfigured, isFalse);
    });

    test('the CamerPay payload has no mode field — liveReady alone decides', () {
      final status = PaymentsStatus.fromJson(const {'liveReady': true});
      expect(status.isLive, isTrue);
      expect(status.mode, 'live');
    });

    test('no mode and not live reports test, never a blank label', () {
      final status = PaymentsStatus.fromJson(const {'liveReady': false});
      expect(status.mode, 'test');
      expect(status.shortLabel, 'TEST');
    });
  });

  group('the old Notch Pay shape still parses', () {
    test('a legacy live payload keeps working', () {
      final status = PaymentsStatus.fromJson(const {
        'mode': 'live',
        'liveReady': true,
        'notchpayConfigured': true,
      });
      expect(status.isLive, isTrue);
      expect(status.providerConfigured, isTrue);
    });

    test('a legacy test payload stays test', () {
      final status = PaymentsStatus.fromJson(const {
        'mode': 'test',
        'liveReady': false,
      });
      expect(status.isLive, isFalse);
    });
  });

  test('the unknown default never claims to be live', () {
    expect(PaymentsStatus.unknown.isLive, isFalse);
    expect(PaymentsStatus.unknown.shortLabel, 'TEST');
  });
}
