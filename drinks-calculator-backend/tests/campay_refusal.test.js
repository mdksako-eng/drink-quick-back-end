/**
 * What CamerPay refused, in our words.
 *
 * The refusal that started this file, seen live on 2026-10-14, went straight onto the
 * customer's screen:
 *   "Votre période d'essai gratuite s'est terminée le 12/10/2026. Activez un plan
 *    pour reprendre. https://camerpay.biz/client/subscription"
 * A third-party sentence, in one language, linking to a portal the user cannot use.
 * The rule now: the app gets a stable code it translates, the provider's words are
 * kept for the log, and they are surfaced as detail only where they are actionable.
 *
 * Run with: npm test
 */
const refusal = require('../utils/campayRefusal');

const LIVE_MESSAGE =
  "Votre période d'essai gratuite s'est terminée le 12/10/2026. Activez un plan pour reprendre. https://camerpay.biz/client/subscription";

describe('the account itself being inactive', () => {
  test('the live refusal is recognised as an account problem', () => {
    const result = refusal.classify({ status: 402, message: LIVE_MESSAGE });
    expect(result.code).toBe(refusal.CODES.ACCOUNT_INACTIVE);
    expect(result.accountLevel).toBe(true);
  });

  test('the wordings we saw are matched, and an unknown refusal stays a quota', () => {
    expect(refusal.classify({ status: 402, message: LIVE_MESSAGE }).code)
      .toBe(refusal.CODES.ACCOUNT_INACTIVE);
    expect(
      refusal.classify({
        status: 402,
        message: 'Your free trial has ended. Activate a plan to continue.',
      }).code
    ).toBe(refusal.CODES.ACCOUNT_INACTIVE);
    expect(
      refusal.classify({ status: 402, message: 'Activez un plan pour reprendre.' }).code
    ).toBe(refusal.CODES.ACCOUNT_INACTIVE);
    // A refusal we cannot attribute to the account stays what it was: a limit.
    expect(
      refusal.classify({ status: 402, message: 'Volume limit reached for this month' }).code
    ).toBe(refusal.CODES.QUOTA);
  });

  test('an upgrade link alone is enough (a payload may carry no prose)', () => {
    const result = refusal.classify({
      status: 402,
      message: 'Payment refused',
      upgradeUrl: 'https://camerpay.biz/client/subscription',
    });
    expect(result.code).toBe(refusal.CODES.ACCOUNT_INACTIVE);
  });

  test('a company KYC limit is NOT read as an account problem', () => {
    const result = refusal.classify({
      status: 402,
      message: 'Monthly volume limit reached for your KYC tier',
      upgradeUrl: 'https://camerpay.biz/kyc',
    });
    expect(result.code).toBe(refusal.CODES.QUOTA);
    expect(result.accountLevel).toBe(false);
  });
});

describe('the other refusals', () => {
  test('a rejected token and a refused request are told apart', () => {
    expect(refusal.classify({ status: 401, message: 'Unauthorized' }).code)
      .toBe(refusal.CODES.TOKEN);
    expect(refusal.classify({ status: 403, message: 'Forbidden' }).code)
      .toBe(refusal.CODES.TOKEN);
    expect(
      refusal.classify({ status: 422, message: 'subscriberMsisdn: not a valid string' }).code
    ).toBe(refusal.CODES.REQUEST_REJECTED);
  });

  test('anything unrecognised still gets a code rather than a raw sentence', () => {
    expect(refusal.classify({}).code).toBe(refusal.CODES.UNKNOWN);
    expect(refusal.classify({ status: 502, message: 'Bad gateway' }).code)
      .toBe(refusal.CODES.UNKNOWN);
  });
});

describe('the sentence the user is shown', () => {
  test('every code has one, and none of them is the provider prose', () => {
    for (const code of Object.values(refusal.CODES)) {
      const message = refusal.userMessageFor(code);
      expect(typeof message).toBe('string');
      expect(message.length).toBeGreaterThan(10);
      expect(message).not.toMatch(/camerpay\.biz|essai|trial/i);
      // Never a machine code either: this text can end up on screen.
      expect(message).not.toMatch(/^campay_/);
    }
  });

  test('only the actionable cases show the provider detail', () => {
    expect(refusal.providerDetailIsUseful(refusal.CODES.QUOTA)).toBe(true);
    expect(refusal.providerDetailIsUseful(refusal.CODES.REQUEST_REJECTED)).toBe(true);
    expect(refusal.providerDetailIsUseful(refusal.CODES.ACCOUNT_INACTIVE)).toBe(false);
    expect(refusal.providerDetailIsUseful(refusal.CODES.TOKEN)).toBe(false);
    expect(refusal.providerDetailIsUseful(refusal.CODES.UNKNOWN)).toBe(false);
  });
});
