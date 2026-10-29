/**
 * POST /payment/initiate must never start a payment - no database required.
 *
 * It was the legacy Notch Pay path the till fell back to when a company had not
 * connected CamerPay. On test keys it would start a sale that reports as paid
 * while nothing was collected - money the shop never received, recorded as
 * received. The route now refuses unconditionally and the rail is deleted.
 *
 * Run with: npm test
 */
const fs = require('fs');
const path = require('path');

const root = path.join(__dirname, '..');
const read = (rel) => fs.readFileSync(path.join(root, rel), 'utf8');

describe('the legacy payment rail refuses when it cannot collect', () => {
  test('/payment/initiate refuses and points the company at CamerPay', () => {
    const routes = read('routes/payment.routes.js');

    expect(routes).toContain("code: 'campay_not_connected'");
    // A refusal, not a success: the till must not record a sale as paid.
    expect(routes).toContain('success: false');
    // The retired rail is gone: nothing can start a Notch Pay payment.
    expect(routes).toContain('CamerPay is the B2C rail');
    expect(routes).not.toContain('notchpay');

    // The retired subscription routes are deleted, not merely unreachable.
    const subs = read('routes/subscriptions.js');
    expect(subs).not.toContain('notchpay');
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
});
