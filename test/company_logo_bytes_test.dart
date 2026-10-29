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
    test('liveReady alone decides live (CamerPay reports no mode)', () {
      expect(
        const PaymentsStatus(mode: 'live', liveReady: true).isLive,
        isTrue,
      );
      expect(
        const PaymentsStatus(mode: 'live', liveReady: false).isLive,
        isFalse,
      );
      // The CamerPay payload has no `mode` field at all, so demanding
      // `mode == 'live'` kept the app on TEST forever while real money moved.
      // `liveReady` is the honest answer — see payments_status_service.dart.
      expect(
        const PaymentsStatus(mode: 'test', liveReady: true).isLive,
        isTrue,
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
        'configured': true,
        'accountDeclaredLive': true,
        'liveReady': true,
        'hint': 'CamerPay account declared live',
      });
      expect(status.mode, 'live');
      expect(status.liveReady, isTrue);
      expect(status.providerConfigured, isTrue);
      expect(status.hint, 'CamerPay account declared live');
    });

    test('survives a thin payload without claiming to be live', () {
      // A payload with nothing live reports 'test' — never a blank label and
      // never 'unknown' (that is only the static default).
      expect(PaymentsStatus.fromJson(const {}).mode, 'test');
      expect(PaymentsStatus.fromJson(const {}).isLive, isFalse);
    });
  });
}
