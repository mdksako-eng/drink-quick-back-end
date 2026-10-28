/**
 * The legacy rail must not take money it cannot collect - no database required.
 *
 * POST /payment/initiate is the Notch Pay path the till falls back to when a
 * company has not connected CamerPay. On test keys it would start a sale that
 * reports as paid while nothing was collected - money the shop never received,
 * recorded as received. The route must therefore refuse when
 * PAYMENTS_REQUIRE_LIVE is on.
 *
 * Run with: npm test
 */
const fs = require('fs');
const path = require('path');

const root = path.join(__dirname, '..');
const read = (rel) => fs.readFileSync(path.join(root, rel), 'utf8');

describe('the legacy payment rail refuses when it cannot collect', () => {
  test('/payment/initiate guards on liveKeyRequired and notchpay.isLive', () => {
    const routes = read('routes/payment.routes.js');

    expect(routes).toContain('paymentGuard.liveKeyRequired()');
    expect(routes).toContain('notchpay.isLive()');
    expect(routes).toContain("code: 'payment_rail_not_live'");
    // A refusal, not a success: the till must not record a sale as paid.
    expect(routes).toContain('success: false');
  });

  test('the switch is off unless the operator asks for it', () => {
    const guard = require('../utils/paymentGuard');
    const savedGeneral = process.env.PAYMENTS_REQUIRE_LIVE;
    const savedLegacy = process.env.NOTCHPAY_REQUIRE_LIVE;

    try {
      delete process.env.PAYMENTS_REQUIRE_LIVE;
      delete process.env.NOTCHPAY_REQUIRE_LIVE;
      expect(guard.liveKeyRequired()).toBe(false);

      process.env.PAYMENTS_REQUIRE_LIVE = 'true';
      expect(guard.liveKeyRequired()).toBe(true);

      delete process.env.PAYMENTS_REQUIRE_LIVE;
      process.env.NOTCHPAY_REQUIRE_LIVE = 'true';
      expect(guard.liveKeyRequired()).toBe(true);
    } finally {
      if (savedGeneral === undefined) delete process.env.PAYMENTS_REQUIRE_LIVE;
      else process.env.PAYMENTS_REQUIRE_LIVE = savedGeneral;
      if (savedLegacy === undefined) delete process.env.NOTCHPAY_REQUIRE_LIVE;
      else process.env.NOTCHPAY_REQUIRE_LIVE = savedLegacy;
    }
  });

  test('notchpay.isLive agrees with the reported key mode', () => {
    const notchpay = require('../utils/notchpay');

    expect(typeof notchpay.isLive()).toBe('boolean');
    expect(notchpay.isLive()).toBe(notchpay.status().mode === 'live');
  });
});
