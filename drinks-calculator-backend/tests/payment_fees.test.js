// backend/tests/payment_fees.test.js
// The commission rules: who pays it, how it rounds, and how "fees included in
// the payment" is computed before we ever call CamerPay.
const {
  METHODS,
  FEE_MODES,
  providerAmountLimits,
  validateAgainstLimits,
  feeFor,
  netFromGross,
  grossUpFor,
  payerCoversFee,
  chargeFor,
  ratesFromEnv,
  ZERO_RATES,
} = require('../utils/paymentFees');

describe('provider amount limits', () => {
  test('exposes the four CamerPay methods', () => {
    expect(METHODS).toEqual(['orange_money', 'mtn_momo', 'stripe', 'paypal']);
  });

  test('publishes the documented min/max per method', () => {
    expect(providerAmountLimits('orange_money')).toEqual({ min: 100, max: 1000000 });
    expect(providerAmountLimits('mtn_momo')).toEqual({ min: 100, max: 1000000 });
    expect(providerAmountLimits('stripe')).toEqual({ min: 300, max: 5000000 });
    expect(providerAmountLimits('paypal')).toEqual({ min: 600, max: 5000000 });
  });

  test('has no limits for an unknown method', () => {
    expect(providerAmountLimits('bitcoin')).toBeNull();
  });

  test('validates amounts at the boundaries', () => {
    expect(validateAgainstLimits('orange_money', 99).reason).toBe('below_min');
    expect(validateAgainstLimits('orange_money', 100).ok).toBe(true);
    expect(validateAgainstLimits('orange_money', 1000000).ok).toBe(true);
    expect(validateAgainstLimits('orange_money', 1000001).reason).toBe('above_max');
    expect(validateAgainstLimits('stripe', 250).reason).toBe('below_min');
    expect(validateAgainstLimits('stripe', 300).ok).toBe(true);
  });

  test('rejects junk amounts and unknown methods', () => {
    expect(validateAgainstLimits('orange_money', 0).reason).toBe('invalid_amount');
    expect(validateAgainstLimits('orange_money', 'soon').reason).toBe('invalid_amount');
    expect(validateAgainstLimits('bitcoin', 5000).reason).toBe('unknown_method');
  });
});

describe('feeFor — absorbed model (CamerPay deducts from the merchant)', () => {
  test('zero rates leave the amount untouched', () => {
    expect(feeFor('orange_money', 5000)).toEqual({
      method: 'orange_money', gross: 5000, fee: 0, net: 5000,
    });
  });

  test('applies basis points and rounds the fee up', () => {
    const rates = { ...ZERO_RATES, orange_money: { bps: 150, flat: 0 } };
    expect(feeFor('orange_money', 5000, rates)).toEqual({
      method: 'orange_money', gross: 5000, fee: 75, net: 4925,
    });
    // 333 XAF at 1.5 % = 4.995 → the provider keeps 5, not 4.
    expect(feeFor('orange_money', 333, rates).fee).toBe(5);
  });

  test('adds a flat fee on top of the percentage', () => {
    const rates = { ...ZERO_RATES, mtn_momo: { bps: 100, flat: 25 } };
    expect(feeFor('mtn_momo', 5000, rates).fee).toBe(75);
  });

  test('never lets the fee exceed the amount', () => {
    const rates = { ...ZERO_RATES, stripe: { bps: 100, flat: 1000 } };
    expect(feeFor('stripe', 300, rates).fee).toBe(300);
    expect(feeFor('stripe', 300, rates).net).toBe(0);
  });

  test('netFromGross matches feeFor', () => {
    const rates = { ...ZERO_RATES, stripe: { bps: 290, flat: 0 } };
    expect(netFromGross('stripe', 10000, rates)).toBe(feeFor('stripe', 10000, rates).net);
  });
});
describe('grossUpFor — the payer carries the fee', () => {
  const rates = {
    ...ZERO_RATES,
    orange_money: { bps: 150, flat: 0 },
    stripe: { bps: 290, flat: 50 },
    paypal: { bps: 340, flat: 100 },
  };

  test('the merchant nets exactly the price asked for', () => {
    for (const method of METHODS) {
      for (const target of [600, 5000, 15000, 99999]) {
        const { gross, net, fee } = grossUpFor(method, target, rates);
        expect(net).toBe(target);
        expect(gross).toBe(target + fee);
        expect(feeFor(method, gross, rates).net).toBe(target);
      }
    }
  });

  test('is an identity when there is no fee', () => {
    expect(grossUpFor('mtn_momo', 5000)).toEqual({
      method: 'mtn_momo', gross: 5000, fee: 0, net: 5000,
    });
  });

  test('a flat fee is simply added', () => {
    const flatOnly = { ...ZERO_RATES, orange_money: { bps: 0, flat: 100 } };
    const up = grossUpFor('orange_money', 5000, flatOnly);
    expect(up.gross).toBe(5100);
    expect(up.net).toBe(5000);
  });
});

describe('chargeFor — what to ask the payer', () => {
  const rates = { ...ZERO_RATES, orange_money: { bps: 150, flat: 0 } };

  test('absorbed: the payer pays the price', () => {
    expect(chargeFor({ netPrice: 5000, method: 'orange_money', rates })).toEqual({
      charge: 5000, fee: 75, net: 4925, mode: FEE_MODES.ABSORBED, method: 'orange_money',
    });
  });

  test('gross_up: the payer pays more so the merchant receives the price', () => {
    const charge = chargeFor({
      netPrice: 5000, method: 'orange_money', rates, mode: FEE_MODES.GROSS_UP,
    });
    expect(charge.charge).toBe(5077);
    expect(charge.net).toBe(5000);
    expect(charge.fee).toBe(77);
  });

  test('payerCoversFee only for the gross-up mode', () => {
    expect(payerCoversFee(FEE_MODES.GROSS_UP)).toBe(true);
    expect(payerCoversFee(FEE_MODES.ABSORBED)).toBe(false);
    expect(payerCoversFee(undefined)).toBe(false);
  });
});

describe('ratesFromEnv — rates are contractual, so they come from configuration', () => {
  test('reads the JSON override', () => {
    const rates = ratesFromEnv({
      CAMERPAY_FEE_RATES: JSON.stringify({ orange_money: { bps: 150, flat: 0 } }),
    });
    expect(rates.orange_money).toEqual({ bps: 150, flat: 0 });
    expect(rates.stripe).toEqual({ bps: 0, flat: 0 });
  });

  test('reads the per-method variables', () => {
    const rates = ratesFromEnv({
      CAMERPAY_FEE_MTN_MOMO_BPS: '120',
      CAMERPAY_FEE_MTN_MOMO_FLAT: '25',
    });
    expect(rates.mtn_momo).toEqual({ bps: 120, flat: 25 });
  });

  test('per-method variables win over the JSON override', () => {
    const rates = ratesFromEnv({
      CAMERPAY_FEE_RATES: JSON.stringify({ stripe: { bps: 100, flat: 0 } }),
      CAMERPAY_FEE_STRIPE_BPS: '290',
    });
    expect(rates.stripe.bps).toBe(290);
  });

  test('a malformed override does not silently zero the per-method rates', () => {
    const warn = jest.spyOn(console, 'warn').mockImplementation(() => {});
    const rates = ratesFromEnv({
      CAMERPAY_FEE_RATES: '{not json',
      CAMERPAY_FEE_PAYPAL_BPS: '340',
    });
    expect(rates.paypal.bps).toBe(340);
    expect(warn).toHaveBeenCalled();
    warn.mockRestore();
  });

  test('defaults to zero for every method', () => {
    expect(ratesFromEnv({})).toEqual(ZERO_RATES);
  });
});

