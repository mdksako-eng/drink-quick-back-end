// tests/payment_qr.test.js
// The QR on the till screen is the customer's way into the payment page, so it
// must be a real PNG of the checkout URL — and a broken encoder must never take
// a payment down with it.
const { paymentQrDataUri, QR_OPTIONS } = require('../utils/paymentQr');

// Rendering a 512px PNG costs 40-400 ms here (first call warms the encoder), and
// this repo lives on a OneDrive folder where Jest start-up is slow; the default
// 5 s budget made correct tests look broken.
jest.setTimeout(30000);

const PNG_SIGNATURE = Buffer.from([0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a]);

function pngFromDataUri(uri) {
  expect(uri.startsWith('data:image/png;base64,')).toBe(true);
  return Buffer.from(uri.split(',')[1], 'base64');
}

describe('paymentQrDataUri', () => {
  test('encodes a checkout URL as an inline PNG', async () => {
    const uri = await paymentQrDataUri('https://pay.camerpay.biz/t/abc123');
    const png = pngFromDataUri(uri);
    expect(png.subarray(0, 8).equals(PNG_SIGNATURE)).toBe(true);
    expect(png.length).toBeGreaterThan(100);
  });

  test('is deterministic for the same URL', async () => {
    const a = await paymentQrDataUri('https://pay.camerpay.biz/t/same');
    const b = await paymentQrDataUri('https://pay.camerpay.biz/t/same');
    expect(a).toBe(b);
  });

  test('two different URLs produce different pictures', async () => {
    const a = await paymentQrDataUri('https://pay.camerpay.biz/t/one');
    const b = await paymentQrDataUri('https://pay.camerpay.biz/t/two');
    expect(a).not.toBe(b);
  });

  test('returns an empty string instead of throwing when there is no URL', async () => {
    expect(await paymentQrDataUri('')).toBe('');
    expect(await paymentQrDataUri(null)).toBe('');
    expect(await paymentQrDataUri(undefined)).toBe('');
    expect(await paymentQrDataUri(42)).toBe('');
  });

  test('stays small enough to send inline', async () => {
    const uri = await paymentQrDataUri('https://pay.camerpay.biz/t/abc123');
    // A till response must not balloon: keep this well under 20 KB.
    expect(uri.length).toBeLessThan(20000);
    expect(QR_OPTIONS.errorCorrectionLevel).toBe('M');
  });
});
