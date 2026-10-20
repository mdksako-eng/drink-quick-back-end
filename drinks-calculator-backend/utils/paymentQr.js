// utils/paymentQr.js
// Renders a payment link as a QR code the till can show the customer.
//
// WHY THIS LIVES ON THE SERVER (and not in the Flutter app):
//  - the app then needs no QR package at all, so no new pub dependency and no
//    resolution risk on web/desktop/Android;
//  - a payment URL must never be sent to a third-party image service, so the
//    picture has to be drawn locally — here, in the same request that created
//    the payment, which also guarantees the QR matches THIS sale;
//  - the same helper can later print the QR on a receipt or a table card.
//
// The PNG is returned inline as a data URI so the till draws it with
// `Image.memory(base64Decode(...))` — no extra HTTP round-trip, no storage.
const QRCode = require('qrcode');

/// Tuned for a phone camera held ~30 cm from a till screen: medium error
/// correction survives a scratched/glary screen, 512 px stays sharp on a tablet
/// while keeping the response small (~2-4 KB).
const QR_OPTIONS = {
  type: 'image/png',
  errorCorrectionLevel: 'M',
  margin: 2,
  width: 512,
};

/**
 * @param {string} url the checkout page to encode
 * @returns {Promise<string>} `data:image/png;base64,...`, or '' when there is
 *   nothing to encode or the encoder fails — a payment must never fail because
 *   a picture could not be drawn.
 */
async function paymentQrDataUri(url) {
  if (!url || typeof url !== 'string') return '';
  try {
    return await QRCode.toDataURL(url, QR_OPTIONS);
  } catch {
    return '';
  }
}

module.exports = { paymentQrDataUri, QR_OPTIONS };
