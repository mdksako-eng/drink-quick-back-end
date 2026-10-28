// utils/whatsapp_link_helper.dart
//
// Delivers a payment link to a customer over WhatsApp with no API, no Meta
// Business account and no per-message fee: wa.me is a click-to-chat URL that
// opens WhatsApp with the message pre-filled, and the cashier taps send. The
// message therefore leaves from the cashier's own WhatsApp, which is the
// trade-off for it being free.
//
// THE TRAP THIS EXISTS TO AVOID
//   wa.me accepts only the INTERNATIONAL form: country code + national number,
//   digits only — no "+", no spaces, and no leading zero. A Cameroonian number is
//   written locally as 6XX XX XX XX, so pasting that straight into the link
//   produces a URL that resolves to nothing, and WhatsApp fails SILENTLY. The
//   cashier types the natural local format and this converts it.
//
// Pure on purpose: no widget, no I/O, so it is unit-testable (see
// test/whatsapp_link_helper_test.dart).
import 'phone_helper.dart';

/// Country code used when the caller does not supply one (Cameroon).
const String kDefaultDialCode = '237';

/// Fewest national digits that can be a real subscriber number. Cameroon uses 9
/// (6XXXXXXXX); 8 is the floor so a slightly short entry is still attempted.
const int kMinNationalDigits = 8;

/// Builds a `wa.me` click-to-chat link carrying [message], or **null** when
/// [number] cannot be a usable WhatsApp number.
///
/// Returning null lets the caller disable the send button instead of opening
/// WhatsApp on a link that would fail quietly.
///
/// Accepted inputs, all normalised to `dial + national`:
///   `6XX XX XX XX`, `06XX XX XX XX`, `+237 6XX XX XX XX`, `2376XXXXXXXX`
String? buildWhatsAppPaymentLink({
  required String number,
  required String message,
  String dialCode = kDefaultDialCode,
}) {
  final dial = PhoneHelper.digitsOnly(dialCode);
  var digits = PhoneHelper.digitsOnly(number);
  if (digits.isEmpty) return null;

  final alreadyInternational =
      dial.isNotEmpty && digits.startsWith(dial) && digits.length > kMinNationalDigits;

  if (!alreadyInternational) {
    digits = PhoneHelper.stripLeadingZero(digits);
    if (digits.length < kMinNationalDigits) return null;
    digits = '$dial$digits';
  }

  // Sanity floor on the final form: country code plus a real national number.
  if (digits.length <= kMinNationalDigits) return null;

  return 'https://wa.me/$digits?text=${Uri.encodeComponent(message)}';
}
