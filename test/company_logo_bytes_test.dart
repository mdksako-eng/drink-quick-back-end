// test/company_logo_bytes_test.dart
// The PDF exports draw the company logo from raw bytes; these tests lock down
// what is fetchable and that a missing/odd logo never throws.
import 'package:flutter_test/flutter_test.dart';
import 'package:drinks_calculator_fixed/services/payments_status_service.dart';
import 'package:drinks_calculator_fixed/utils/company_logo_bytes.dart';

void main() {
  setUp(() => CompanyLogoBytes.resetCache());

  group('isFetchableUrl', () {
    test('accepts http and https', () {
      expect(CompanyLogoBytes.isFetchableUrl('https://x/y.png'), isTrue);
      expect(CompanyLogoBytes.isFetchableUrl('http://x/y.png'), isTrue);
    });

    test('rejects data URIs, local paths and blanks', () {
      expect(CompanyLogoBytes.isFetchableUrl('data:image/png;base64,AAA'),
          isFalse);
      expect(CompanyLogoBytes.isFetchableUrl('C:/pics/logo.png'), isFalse);
      expect(CompanyLogoBytes.isFetchableUrl(''), isFalse);
      expect(CompanyLogoBytes.isFetchableUrl('placeholder.com/150'), isFalse);
    });
  });

  group('fromUrl', () {
    test('returns null for unusable input instead of throwing', () async {
      expect(await CompanyLogoBytes.fromUrl(null), isNull);
      expect(await CompanyLogoBytes.fromUrl('   '), isNull);
      expect(await CompanyLogoBytes.fromUrl('data:image/png;base64,AAAA'),
          isNull);
    });

    test('returns null when the host is unreachable', () async {
      final bytes = await CompanyLogoBytes.fromUrl(
          'https://this-host-does-not-exist-9f8a7b.invalid/logo.png');
      expect(bytes, isNull);
    });
  });

  group('PaymentsStatus', () {
    test('only live + ready counts as live', () {
      expect(
        const PaymentsStatus(mode: 'live', liveReady: true).isLive,
        isTrue,
      );
      expect(
        const PaymentsStatus(mode: 'live', liveReady: false).isLive,
        isFalse,
      );
      expect(
        const PaymentsStatus(mode: 'test', liveReady: true).isLive,
        isFalse,
      );
      expect(PaymentsStatus.unknown.isLive, isFalse);
    });

    test('labels the mode for the subscription banner', () {
      expect(const PaymentsStatus(mode: 'live', liveReady: true).shortLabel,
          'LIVE');
      expect(const PaymentsStatus(mode: 'test', liveReady: false).shortLabel,
          'TEST');
    });

    test('parses the backend health payload', () {
      final status = PaymentsStatus.fromJson({
        'mode': 'test',
        'liveReady': false,
        'notchpayConfigured': true,
        'hint': 'add live keys',
      });
      expect(status.mode, 'test');
      expect(status.liveReady, isFalse);
      expect(status.notchPayConfigured, isTrue);
      expect(status.hint, 'add live keys');
    });

    test('falls back to notchpayMode and survives a thin payload', () {
      expect(PaymentsStatus.fromJson({'notchpayMode': 'live'}).mode, 'live');
      expect(PaymentsStatus.fromJson(const {}).mode, 'unknown');
    });
  });
}
