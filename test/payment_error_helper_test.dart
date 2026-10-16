// test/payment_error_helper_test.dart
// A refused payment must never put the provider's own sentence in front of a user.
// The regression this guards is the one seen live on 2026-10-14, printed straight
// onto the screen:
//   "Votre période d'essai gratuite s'est terminée le 12/10/2026. Activez un plan
//    pour reprendre. https://camerpay.biz/client/subscription"
import 'package:flutter_test/flutter_test.dart';
import 'package:drinks_calculator_fixed/utils/i18n.dart';
import 'package:drinks_calculator_fixed/utils/payment_error_helper.dart';

const String providerProse =
    "Votre période d'essai gratuite s'est terminée le 12/10/2026. "
    'Activez un plan pour reprendre. https://camerpay.biz/client/subscription';

PaymentFailure failure(
  String code, {
  String? providerMessage,
  bool accountLevel = false,
}) =>
    PaymentFailure(
      code: code,
      providerMessage: providerMessage,
      providerCode: 'some_provider_code',
      accountLevel: accountLevel,
    );

void main() {
  group('which sentence is shown', () {
    test('each code has its own translated sentence', () {
      expect(PaymentErrorHelper.messageKey('campay_account_inactive'),
          'payErrAccountInactive');
      expect(PaymentErrorHelper.messageKey('campay_quota'), 'payErrQuota');
      expect(PaymentErrorHelper.messageKey('campay_token'), 'payErrToken');
      expect(
          PaymentErrorHelper.messageKey('campay_request_rejected'),
          'payErrRequestRejected');
      expect(PaymentErrorHelper.messageKey('campay_not_configured'),
          'payErrNotConfigured');
    });

    test('an unknown or missing code still gets a sentence', () {
      expect(PaymentErrorHelper.messageKey('anything_else'), 'payErrGeneric');
      expect(PaymentErrorHelper.codeOf(null), PaymentErrorHelper.unknownCode);
      expect(PaymentErrorHelper.message(null), t('payErrGeneric'));
    });

    test('every code maps to a key that actually exists in i18n', () {
      // A typo here would render the raw key on screen: t() falls back to it.
      final codes = [
        'campay_account_inactive',
        'campay_quota',
        'campay_token',
        'campay_request_rejected',
        'campay_not_configured',
        'campay_error',
        'something_new',
      ];
      for (final code in codes) {
        final key = PaymentErrorHelper.messageKey(code);
        expect(t(key), isNot(key), reason: 'missing translation for $key');
        expect(t(key).trim(), isNotEmpty);
      }
    });
  });

  group('the provider is never quoted on screen', () {
    test('a failure carrying the live prose shows our sentence instead', () {
      final error = failure('campay_account_inactive', providerMessage: providerProse);
      final shown = PaymentErrorHelper.messageWithDetail(error);

      expect(shown, t('payErrAccountInactive'));
      expect(shown.contains('camerpay.biz'), isFalse);
      expect(shown.contains('essai'), isFalse);
      expect(shown.contains("12/10/2026"), isFalse);
    });

    test('an account-level refusal hides the prose even if it looks actionable', () {
      // The customer cannot fix our payment account, so the detail is not shown.
      expect(
        PaymentErrorHelper.detail(
            failure('campay_account_inactive', providerMessage: providerProse)),
        isNull,
      );
    });

    test('a network or HTTP mess is never shown either', () {
      final network = PaymentErrorHelper.fromResponse({
        'success': false,
        'error': 'Network error: SocketException: Failed host lookup',
      });
      final http = PaymentErrorHelper.fromResponse({
        'success': false,
        'error': 'HTTP 500',
      });
      expect(PaymentErrorHelper.messageWithDetail(network), t('payErrGeneric'));
      expect(PaymentErrorHelper.messageWithDetail(http), t('payErrGeneric'));
    });
  });

  group('when the provider detail IS worth showing', () {
    test('a KYC limit keeps it, under our sentence', () {
      final error = failure(
        'campay_quota',
        providerMessage: 'Upload your ID to raise the monthly limit.',
      );
      expect(PaymentErrorHelper.detail(error),
          'Upload your ID to raise the monthly limit.');
      expect(
        PaymentErrorHelper.messageWithDetail(error),
        '${t('payErrQuota')}\nUpload your ID to raise the monthly limit.',
      );
    });

    test('a refused request keeps it too — it names the field', () {
      final error = failure(
        'campay_request_rejected',
        providerMessage: 'subscriberMsisdn: not a valid string',
      );
      expect(PaymentErrorHelper.messageWithDetail(error),
          contains('subscriberMsisdn'));
    });

    test('an empty detail adds nothing', () {
      expect(
        PaymentErrorHelper.messageWithDetail(
            failure('campay_quota', providerMessage: '   ')),
        t('payErrQuota'),
      );
    });
  });

  group('reading a refusal the app decoded itself', () {
    test('the collection path returns a map: code, detail and account flag', () {
      final decoded = PaymentErrorHelper.fromResponse({
        'success': false,
        'code': 'campay_account_inactive',
        'providerMessage': providerProse,
        'providerCode': 'trial_over',
        'accountLevel': true,
      });
      expect(decoded.code, 'campay_account_inactive');
      expect(decoded.providerMessage, providerProse);
      expect(decoded.providerCode, 'trial_over');
      expect(decoded.accountLevel, isTrue);
      expect(decoded.toString(), 'PaymentFailure(campay_account_inactive)');
    });

    test('an empty map falls back to the generic code', () {
      expect(PaymentErrorHelper.fromResponse(null).code,
          PaymentErrorHelper.unknownCode);
      expect(PaymentErrorHelper.fromResponse(const {}).code,
          PaymentErrorHelper.unknownCode);
    });
  });
}
