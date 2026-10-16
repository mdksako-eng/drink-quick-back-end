// utils/payment_error_helper.dart
// Turning a refused payment into something a customer can read.
//
// The provider explains itself in its own prose, in its own language, with links to
// its own portal. Seen live on 2026-10-14, straight onto the screen:
//   "Votre période d'essai gratuite s'est terminée le 12/10/2026. Activez un plan
//    pour reprendre. https://camerpay.biz/client/subscription"
// That is a support ticket, not a customer message: it names a third party, exists
// in one language only, and links somewhere the user cannot act.
//
// So the backend classifies the refusal into a code (utils/campayRefusal.js), this
// helper maps that code to an i18n key, and the provider's own words are kept for
// the log — shown as a second line only where they are actionable (a KYC limit names
// the document that unlocks the next tier).
//
// Pure, so the mapping is unit tested instead of living in the widget.
import 'i18n.dart';

/// A payment the server refused, carrying the machine-readable code.
class PaymentFailure implements Exception {
  const PaymentFailure({
    required this.code,
    this.providerMessage,
    this.providerCode,
    this.accountLevel = false,
  });

  /// e.g. 'campay_account_inactive', 'campay_quota' — see utils/campayRefusal.js.
  final String code;

  /// The provider's own wording, for the log and for [PaymentErrorHelper.detail].
  final String? providerMessage;

  /// The provider's own error code, for support.
  final String? providerCode;

  /// True when the payment account itself is the problem, so the customer can do
  /// nothing about it.
  final bool accountLevel;

  /// Never includes the provider's prose: this string can end up on screen.
  @override
  String toString() => 'PaymentFailure($code)';
}

class PaymentErrorHelper {
  PaymentErrorHelper._();

  /// Used when the backend sent no code at all (older server, network failure).
  static const String unknownCode = 'campay_error';

  /// The code behind any error, whatever shape it arrived in.
  static String codeOf(Object? error) =>
      error is PaymentFailure ? error.code : unknownCode;

  /// A refusal the app already decoded into a map.
  ///
  /// The per-company collection path returns its answer instead of throwing, so the
  /// caller has a Map rather than an Exception — including a plain network failure,
  /// whose text must not be shown either.
  static PaymentFailure fromResponse(Map<String, dynamic>? data) {
    final map = data ?? const <String, dynamic>{};
    return PaymentFailure(
      code: (map['code'] ?? map['error'] ?? unknownCode).toString(),
      providerMessage: map['providerMessage']?.toString(),
      providerCode: map['providerCode']?.toString(),
      accountLevel: map['accountLevel'] == true,
    );
  }

  /// The i18n key for a code. Every code gets a sentence of its own; an unknown one
  /// still gets a sentence rather than the provider's.
  static String messageKey(String code) {
    switch (code) {
      case 'campay_account_inactive':
        return 'payErrAccountInactive';
      case 'campay_quota':
        return 'payErrQuota';
      case 'campay_token':
        return 'payErrToken';
      case 'campay_request_rejected':
        return 'payErrRequestRejected';
      case 'campay_not_configured':
        return 'payErrNotConfigured';
      default:
        return 'payErrGeneric';
    }
  }

  /// What the user reads — translated, and never the provider's own sentence.
  static String message(Object? error) => t(messageKey(codeOf(error)));

  /// Is the provider's wording worth a second line under the message?
  /// Only where it is actionable: a KYC/volume limit names the missing document,
  /// and a refused request says which field the operator rejected.
  static bool providerDetailIsUseful(String code) =>
      code == 'campay_quota' || code == 'campay_request_rejected';

  /// The provider's detail, or null when there is nothing useful to add.
  static String? detail(Object? error) {
    if (error is! PaymentFailure) return null;
    if (!providerDetailIsUseful(error.code)) return null;
    final text = (error.providerMessage ?? '').trim();
    return text.isEmpty ? null : text;
  }

  /// The whole thing to show: our sentence, plus the detail when it helps.
  static String messageWithDetail(Object? error) {
    final detailText = detail(error);
    final headline = message(error);
    return detailText == null ? headline : '$headline\n$detailText';
  }
}
