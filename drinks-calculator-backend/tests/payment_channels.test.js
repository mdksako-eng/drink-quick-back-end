/**
 * Subscription payment rails (card / MTN / Orange) through Notch Pay.
 *
 * Covers the rule the platform asked for:
 *   - all three rails are offered, and each one is translated into a valid
 *     Notch Pay request (locked channel + its country, or an open checkout)
 *   - card is not in Notch Pay's channel list, so it locks to the account's card
 *     channel when there is one and otherwise opens the Collect page
 *   - junk channel strings are rejected instead of being forwarded
 *
 * Run with: npm test
 */
const {
  PROVIDERS,
  SLUGS,
  findCardSlug,
  isCardProvider,
  lockCountryFor,
  resolveChannel,
  summarizeChannels,
} = require('../utils/paymentChannels');

describe('the three rails we sell', () => {
  test('card, MTN and Orange are the offered rails', () => {
    expect(PROVIDERS).toEqual(['card', 'mtn', 'orange']);
  });

  test('MTN and Orange are locked to their Cameroonian channel', () => {
    expect(SLUGS.mtn).toBe('cm.mtn');
    expect(SLUGS.orange).toBe('cm.orange');
  });
});

describe('resolveChannel — what the app sends', () => {
  test("'mtn' becomes a locked cm.mtn request in Cameroon", () => {
    expect(resolveChannel('mtn')).toEqual({
      provider: 'mtn',
      slug: 'cm.mtn',
      lockCountry: 'CM',
      locked: true,
    });
  });

  test("'orange' becomes a locked cm.orange request in Cameroon", () => {
    expect(resolveChannel('orange')).toEqual({
      provider: 'orange',
      slug: 'cm.orange',
      lockCountry: 'CM',
      locked: true,
    });
  });

  test('raw slugs are accepted, and are case/space insensitive', () => {
    expect(resolveChannel(' cm.MTN ')?.slug).toBe('cm.mtn');
    expect(resolveChannel('CM.ORANGE')?.slug).toBe('cm.orange');
  });

  test('card without a known card channel opens the checkout instead of locking', () => {
    expect(resolveChannel('card')).toEqual({
      provider: 'card',
      slug: null,
      lockCountry: null,
      locked: false,
    });
  });

  test('card locks to the account card channel when there is one', () => {
    expect(resolveChannel('card', { cardSlug: 'cm.visa' })).toEqual({
      provider: 'card',
      slug: 'cm.visa',
      lockCountry: 'CM',
      locked: true,
    });
  });

  test('a missing/blank/auto channel means "let the customer choose"', () => {
    ['', null, undefined, 'any', 'AUTO'].forEach((raw) => {
      const resolved = resolveChannel(raw);
      expect(resolved).toEqual({
        provider: 'any',
        slug: null,
        lockCountry: null,
        locked: false,
      });
    });
  });

  test('another country slug is passed through with its own country', () => {
    expect(resolveChannel('ci.mtn')).toEqual({
      provider: 'other',
      slug: 'ci.mtn',
      lockCountry: null, // Ivory Coast is not in our country map
      locked: true,
    });
  });

  test('junk is rejected rather than forwarded to Notch Pay', () => {
    ['drop table', 'cm', 'cm.', 'not a channel', 'cm.mtn;--'].forEach((raw) => {
      expect(resolveChannel(raw)).toBeNull();
    });
  });
});

describe('a locked channel must lock the country too', () => {
  test('Cameroon slugs imply CM', () => {
    expect(lockCountryFor('cm.mtn')).toBe('CM');
    expect(lockCountryFor('cm.orange')).toBe('CM');
  });

  test('unknown prefixes imply nothing', () => {
    expect(lockCountryFor('gh.mtn')).toBeNull();
    expect(lockCountryFor('')).toBeNull();
  });
});

describe('summarizeChannels — what the live account can charge', () => {
  const account = [
    { slug: 'cm.mtn', type: 'mobile_money', countries: ['CM'] },
    { slug: 'cm.orange', type: 'mobile_money', countries: ['CM'] },
  ];

  test('Mobile Money only', () => {
    expect(summarizeChannels(account)).toEqual({
      mtn: true,
      orange: true,
      card: false,
      count: 2,
      slugs: ['cm.mtn', 'cm.orange'],
    });
  });

  test('a card channel is detected', () => {
    const withCard = [...account, { slug: 'cm.visa', type: 'card' }];
    const summary = summarizeChannels(withCard);
    expect(summary.card).toBe(true);
    expect(findCardSlug(withCard)).toBe('cm.visa');
  });

  test('an empty or unusable response is reported as nothing available', () => {
    [null, undefined, [], ['nope'], [{}]].forEach((input) => {
      const summary = summarizeChannels(input);
      expect(summary).toEqual({
        mtn: false,
        orange: false,
        card: false,
        count: 0,
        slugs: [],
      });
    });
  });

  test('the card slug is picked up from alternate field names', () => {
    expect(findCardSlug([{ channel: 'cm.card', type: 'debit_card' }])).toBe('cm.card');
    expect(findCardSlug([{ code: 'cm.card', channel_type: 'bank_card' }])).toBe('cm.card');
  });
});

describe('isCardProvider', () => {
  test('only the card rail is the card rail', () => {
    expect(isCardProvider('card')).toBe(true);
    expect(isCardProvider('CARD')).toBe(true);
    expect(isCardProvider('mtn')).toBe(false);
    expect(isCardProvider('cm.mtn')).toBe(false);
  });
});
