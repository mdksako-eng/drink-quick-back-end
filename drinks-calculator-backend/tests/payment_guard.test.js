/**
 * Payment amounts — the guard that decides whether a paid subscription may be
 * activated. Pure, no database.
 *
 * Covers the rule: pay more (fees, rounding) is fine, pay less is not, and an
 * unknown amount is never a reason to refuse an honest payment.
 *
 * Run with: npm test
 */
const {
  normalizeAmount,
  normalizeCurrency,
  paidAmountMatches,
  shouldEnforce,
} = require('../utils/paymentGuard');

describe('normalizeAmount', () => {
  test('accepts JSON numbers and the driver NUMERIC strings', () => {
    expect(normalizeAmount(5000)).toBe(5000);
    expect(normalizeAmount('5000')).toBe(5000);
    expect(normalizeAmount('15000.00')).toBe(15000);
  });

  test('reports "no amount" as null rather than zero', () => {
    [null, undefined, '', 'nope', NaN].forEach((value) => {
      expect(normalizeAmount(value)).toBeNull();
    });
    expect(normalizeAmount(0)).toBe(0);
  });
});

describe('normalizeCurrency', () => {
  test('upper-cases and trims the code', () => {
    expect(normalizeCurrency(' xaf ')).toBe('XAF');
    expect(normalizeCurrency(null)).toBeNull();
  });
});

describe('paidAmountMatches', () => {
  test('the exact price is accepted', () => {
    const result = paidAmountMatches({
      paidAmount: 5000,
      paidCurrency: 'XAF',
      expectedAmount: 5000,
      expectedCurrency: 'XAF',
    });
    expect(result.ok).toBe(true);
    expect(result.reason).toBe('exact');
  });

  test('paying more is accepted (fees, rounding in the customer favour)', () => {
    expect(
      paidAmountMatches({ paidAmount: 5100, expectedAmount: 5000 }).reason
    ).toBe('overpaid');
    expect(paidAmountMatches({ paidAmount: 5100, expectedAmount: 5000 }).ok).toBe(true);
  });

  test('paying less is refused — a month is not given away', () => {
    const result = paidAmountMatches({ paidAmount: 1, expectedAmount: 5000 });
    expect(result.ok).toBe(false);
    expect(result.reason).toBe('underpaid');
    expect(result.paid).toBe(1);
    expect(result.expected).toBe(5000);
  });

  test('a half unit of tolerance absorbs float noise, not a shortfall', () => {
    expect(paidAmountMatches({ paidAmount: 4999.6, expectedAmount: 5000 }).ok).toBe(true);
    // The 0.5 boundary is inclusive; anything below it is a shortfall.
    expect(paidAmountMatches({ paidAmount: 4999.5, expectedAmount: 5000 }).ok).toBe(true);
    expect(paidAmountMatches({ paidAmount: 4999.4, expectedAmount: 5000 }).ok).toBe(false);
    expect(paidAmountMatches({ paidAmount: 4999, expectedAmount: 5000 }).ok).toBe(false);
  });

  test('the wrong currency is refused', () => {
    const result = paidAmountMatches({
      paidAmount: 5000,
      paidCurrency: 'USD',
      expectedAmount: 5000,
      expectedCurrency: 'XAF',
    });
    expect(result.ok).toBe(false);
    expect(result.reason).toBe('currency_mismatch');
  });

  test('a missing currency on either side is not a mismatch', () => {
    expect(
      paidAmountMatches({ paidAmount: 5000, expectedAmount: 5000 }).ok
    ).toBe(true);
    expect(
      paidAmountMatches({
        paidAmount: 5000,
        paidCurrency: 'XAF',
        expectedAmount: 5000,
      }).ok
    ).toBe(true);
  });

  test('an amount the provider did not repeat is allowed through', () => {
    const result = paidAmountMatches({ expectedAmount: 5000 });
    expect(result.ok).toBe(true);
    expect(result.reason).toBe('amount_unknown');
  });

  test('nothing to compare against is allowed through', () => {
    const result = paidAmountMatches({ paidAmount: 5000 });
    expect(result.ok).toBe(true);
    expect(result.reason).toBe('no_expectation');
  });

  test('a NUMERIC string from the pending row still matches a number', () => {
    const result = paidAmountMatches({
      paidAmount: '15000.00',
      paidCurrency: 'xaf',
      expectedAmount: '15000',
      expectedCurrency: 'XAF',
    });
    expect(result.ok).toBe(true);
    expect(result.reason).toBe('exact');
  });

  test('called with nothing at all it refuses nothing', () => {
    expect(paidAmountMatches().ok).toBe(true);
  });
});

describe('shouldEnforce', () => {
  afterEach(() => {
    delete process.env.NOTCHPAY_ALLOW_UNDERPAYMENT;
  });

  test('on by default', () => {
    expect(shouldEnforce()).toBe(true);
  });

  test('an operator can opt out with NOTCHPAY_ALLOW_UNDERPAYMENT=true', () => {
    process.env.NOTCHPAY_ALLOW_UNDERPAYMENT = 'true';
    expect(shouldEnforce()).toBe(false);
    process.env.NOTCHPAY_ALLOW_UNDERPAYMENT = 'TRUE';
    expect(shouldEnforce()).toBe(false);
    process.env.NOTCHPAY_ALLOW_UNDERPAYMENT = 'false';
    expect(shouldEnforce()).toBe(true);
  });
});
