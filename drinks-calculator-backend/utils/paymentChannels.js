// backend/utils/paymentChannels.js
// Which payment rails a subscription may be charged on, and how to ask Notch Pay
// for them. Pure — no network, no database — so the rules stay testable.
//
// The platform wants three rails to work through ONE provider (Notch Pay):
//   card, mtn, orange.
// Mobile Money is locked by channel slug (cm.mtn / cm.orange). Card is NOT in
// Notch Pay's documented channel list: their Collect page offers the methods the
// account is enabled for. So:
//   - if the account reports a card channel, we lock to it;
//   - otherwise we open the (unlocked) Collect page, where card is one of the
//     choices — and MTN / Orange are there too.
// A locked channel must also lock the country, or Notch Pay rejects the request.

/** Rails the platform sells subscriptions on. */
const PROVIDERS = ['card', 'mtn', 'orange'];

/** Locked channel slugs for the two Cameroonian Mobile Money operators. */
const SLUGS = {
  mtn: 'cm.mtn',
  orange: 'cm.orange',
};

/** Channel `type` values Notch Pay may use for a card rail. */
const CARD_TYPES = [
  'card',
  'cards',
  'debit_card',
  'credit_card',
  'bank_card',
  'visa',
  'mastercard',
];

/** Country implied by a channel slug prefix (only what we sell in). */
const COUNTRY_BY_PREFIX = {
  cm: 'CM',
};

/** Lower-cased, trimmed string — Notch Pay slugs are case-insensitive in practice. */
function normalizeSlug(raw) {
  return String(raw ?? '').trim().toLowerCase();
}

/**
 * The slug of a channel entry, when that entry is a card rail.
 * @returns {string} '' when the entry is not a card.
 */
function cardSlugOf(entry) {
  if (!entry || typeof entry !== 'object') return '';
  const type = normalizeSlug(entry.type ?? entry.channel_type);
  if (!CARD_TYPES.includes(type)) return '';
  return normalizeSlug(entry.slug ?? entry.channel ?? entry.code);
}

/**
 * First card channel in a `/channels` response, or '' when the account has none.
 * @returns {string}
 */
function findCardSlug(channels) {
  const list = Array.isArray(channels) ? channels : [];
  for (let i = 0; i < list.length; i += 1) {
    const slug = cardSlugOf(list[i]);
    if (slug) return slug;
  }
  return '';
}

/** True when the rail is the card rail. */
function isCardProvider(provider) {
  return normalizeSlug(provider) === 'card';
}

/**
 * Country to lock a channel to, derived from its prefix ('cm.mtn' -> 'CM').
 * @returns {string|null}
 */
function lockCountryFor(slug) {
  const s = normalizeSlug(slug);
  const prefix = s.split('.')[0];
  return COUNTRY_BY_PREFIX[prefix] || null;
}

/**
 * Turn whatever the app sent into a Notch Pay request shape.
 *
 * Accepts the short form ('mtn' | 'orange' | 'card' | 'any') and raw slugs
 * ('cm.mtn', 'ci.mtn'). Returns null for anything we cannot honour, so the
 * route answers 400 instead of forwarding junk to Notch Pay.
 *
 * @param {string} raw
 * @param {{ cardSlug?: string }} [options] card slug discovered from the account
 * @returns {{provider: string, slug: string|null, lockCountry: string|null, locked: boolean}|null}
 */
function resolveChannel(raw, { cardSlug = '' } = {}) {
  const value = normalizeSlug(raw);

  if (!value || value === 'any' || value === 'auto') {
    return { provider: 'any', slug: null, lockCountry: null, locked: false };
  }

  if (value === 'mtn' || value === SLUGS.mtn) {
    return {
      provider: 'mtn',
      slug: SLUGS.mtn,
      lockCountry: lockCountryFor(SLUGS.mtn),
      locked: true,
    };
  }

  if (value === 'orange' || value === SLUGS.orange) {
    return {
      provider: 'orange',
      slug: SLUGS.orange,
      lockCountry: lockCountryFor(SLUGS.orange),
      locked: true,
    };
  }

  if (isCardProvider(value)) {
    const slug = normalizeSlug(cardSlug);
    if (!slug) {
      // No card channel on the account: open the Collect page instead of
      // locking to a channel Notch Pay would refuse.
      return { provider: 'card', slug: null, lockCountry: null, locked: false };
    }
    return {
      provider: 'card',
      slug,
      lockCountry: lockCountryFor(slug),
      locked: true,
    };
  }

  // Any other well-formed slug (e.g. 'ci.mtn') is passed through.
  if (/^[a-z]{2}\.[a-z0-9_]+$/.test(value)) {
    return {
      provider: 'other',
      slug: value,
      lockCountry: lockCountryFor(value),
      locked: true,
    };
  }

  return null;
}

/**
 * Which rails the account can actually charge.
 * @param {Array} channels `/channels` items (objects with slug/type)
 * @returns {{mtn: boolean, orange: boolean, card: boolean, count: number, slugs: string[]}}
 */
function summarizeChannels(channels) {
  const list = Array.isArray(channels) ? channels : [];
  const slugs = [];
  let mtn = false;
  let orange = false;
  let card = false;

  list.forEach((entry) => {
    if (!entry || typeof entry !== 'object') return;
    const slug = normalizeSlug(entry.slug ?? entry.channel ?? entry.code);
    if (!slug) return;
    slugs.push(slug);
    if (slug === SLUGS.mtn) mtn = true;
    if (slug === SLUGS.orange) orange = true;
    if (cardSlugOf(entry)) card = true;
  });

  return { mtn, orange, card, count: slugs.length, slugs };
}

module.exports = {
  PROVIDERS,
  SLUGS,
  CARD_TYPES,
  normalizeSlug,
  findCardSlug,
  isCardProvider,
  lockCountryFor,
  resolveChannel,
  summarizeChannels,
};
