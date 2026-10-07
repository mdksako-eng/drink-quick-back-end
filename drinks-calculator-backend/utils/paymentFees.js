// backend/utils/paymentFees.js
// Who pays the CamerPay commission, and how much it is. Pure — no network, no
// database — so the rule stays testable.
//
// What CamerPay does (docs /tarifs): "La commission par transaction est prélevée
// automatiquement sur chaque encaissement réussi", and POST /payment/initiate has
// NO field to hand a fee to the payer. The API does not publish its rates either.
// Two consequences:
//   1. The default model is ABSORBED — the payer pays the price, the provider
//      keeps its commission, the merchant nets less.
//   2. "Fees included in the payment" (gross-up: the payer covers it) must be
//      computed HERE, before we call initiate. Rates are contractual, so they
//      live in configuration and never in code.
//
// Amounts are whole XAF and fees round UP, so a calculation can never leave the
// merchant short of the intended net.

const METHODS = ['orange_money', 'mtn_momo', 'stripe', 'paypal'];

/** How the commission is carried. */
const FEE_MODES = { ABSORBED: 'absorbed', GROSS_UP: 'gross_up' };

/** Per-method min/max published at https://camerpay.biz/docs/endpoints */
const PROVIDER_AMOUNT_LIMITS = {
  orange_money: { min: 100, max: 1000000 },
  mtn_momo: { min: 100, max: 1000000 },
  stripe: { min: 300, max: 5000000 },
  paypal: { min: 600, max: 5000000 },
};

/** @returns {{min:number,max:number}|null} limits for a method, or null. */
function providerAmountLimits(method) {
  return PROVIDER_AMOUNT_LIMITS[method] || null;
}

/**
 * Is this amount acceptable for this method?
 * @returns {{ok:boolean, reason:string, min:number|null, max:number|null}}
 */
function validateAgainstLimits(method, amount) {
  const limit = providerAmountLimits(method);
  const value = Number(amount);
  if (!limit) return { ok: false, reason: 'unknown_method', min: null, max: null };
  if (!Number.isFinite(value) || value <= 0) {
    return { ok: false, reason: 'invalid_amount', min: limit.min, max: limit.max };
  }
  const rounded = Math.round(value);
  if (rounded < limit.min) return { ok: false, reason: 'below_min', min: limit.min, max: limit.max };
  if (rounded > limit.max) return { ok: false, reason: 'above_max', min: limit.min, max: limit.max };
  return { ok: true, reason: 'ok', min: limit.min, max: limit.max };
}

/** Zero-rated until the real contract rates are configured. */
const ZERO_RATES = METHODS.reduce((acc, m) => {
  acc[m] = { bps: 0, flat: 0 };
  return acc;
}, {});

/** Coerce a rate to { bps, flat }; garbage becomes 0 rather than NaN. */
function normalizeRate(rate) {
  const bps = Number(rate && rate.bps);
  const flat = Number(rate && rate.flat);
  return {
    bps: Number.isFinite(bps) && bps >= 0 ? bps : 0,
    flat: Number.isFinite(flat) && flat >= 0 ? flat : 0,
  };
}
/**
 * Rates from configuration, because CamerPay's API does not publish them.
 *  - CAMERPAY_FEE_RATES='{"orange_money":{"bps":150,"flat":0}}' (JSON override)
 *  - CAMERPAY_FEE_ORANGE_MONEY_BPS / CAMERPAY_FEE_ORANGE_MONEY_FLAT (per method)
 * bps = basis points (150 = 1.5 %).
 */
function ratesFromEnv(env = process.env) {
  const rates = {};
  for (const m of METHODS) rates[m] = { ...ZERO_RATES[m] };

  const raw = env.CAMERPAY_FEE_RATES;
  if (raw) {
    try {
      const parsed = JSON.parse(raw);
      for (const m of METHODS) {
        if (parsed && parsed[m]) rates[m] = normalizeRate(parsed[m]);
      }
    } catch (e) {
      // A malformed override must not silently pretend payments are free: keep
      // the zero defaults and make the mistake visible to the operator.
      console.warn('CAMERPAY_FEE_RATES is not valid JSON — using per-method/default rates');
    }
  }

  for (const m of METHODS) {
    const key = m.toUpperCase();
    const bps = Number(env[`CAMERPAY_FEE_${key}_BPS`]);
    const flat = Number(env[`CAMERPAY_FEE_${key}_FLAT`]);
    if (Number.isFinite(bps) && bps >= 0) rates[m].bps = bps;
    if (Number.isFinite(flat) && flat >= 0) rates[m].flat = flat;
  }
  return rates;
}

/**
 * Split a gross amount (what the payer sends) into fee and net.
 * @returns {{method:string, gross:number, fee:number, net:number}}
 */
function feeFor(method, amount, rates = ZERO_RATES) {
  const gross = Math.max(0, Math.round(Number(amount) || 0));
  const rate = normalizeRate((rates || ZERO_RATES)[method]);
  const raw = Math.ceil((gross * rate.bps) / 10000) + rate.flat;
  const fee = Math.min(Math.max(raw, 0), gross);
  return { method, gross, fee, net: gross - fee };
}

/** What the merchant keeps when the payer sends `amount`. */
function netFromGross(method, amount, rates = ZERO_RATES) {
  return feeFor(method, amount, rates).net;
}

/**
 * The inverse: what the payer must send so the merchant nets exactly
 * `netTarget`. Rounds up, then nudges, because the ceiling inside feeFor could
 * otherwise leave the merchant one franc short.
 * @returns {{method:string, gross:number, fee:number, net:number}}
 */
function grossUpFor(method, netTarget, rates = ZERO_RATES) {
  const target = Math.max(0, Math.round(Number(netTarget) || 0));
  const rate = normalizeRate((rates || ZERO_RATES)[method]);
  const divisor = 1 - rate.bps / 10000;
  let gross = divisor > 0
    ? Math.ceil((target + rate.flat) / divisor)
    : target + rate.flat;
  for (let i = 0; i < 6 && netFromGross(method, gross, rates) < target; i += 1) {
    gross += 1;
  }
  const { fee, net } = feeFor(method, gross, rates);
  return { method, gross, fee, net };
}

/** True when the payer carries the commission instead of the merchant. */
function payerCoversFee(mode) {
  return mode === FEE_MODES.GROSS_UP;
}

/**
 * What to ask the payer, given the price the merchant wants to keep.
 * @param {object} params { netPrice, method, rates, mode }
 * @returns {{charge:number, fee:number, net:number, mode:string, method:string}}
 */
function chargeFor({ netPrice, method, rates = ZERO_RATES, mode = FEE_MODES.ABSORBED } = {}) {
  const price = Math.max(0, Math.round(Number(netPrice) || 0));
  if (payerCoversFee(mode)) {
    const { gross, fee, net } = grossUpFor(method, price, rates);
    return { charge: gross, fee, net, mode, method };
  }
  const { fee, net } = feeFor(method, price, rates);
  return { charge: price, fee, net, mode, method };
}

module.exports = {
  METHODS,
  FEE_MODES,
  PROVIDER_AMOUNT_LIMITS,
  ZERO_RATES,
  providerAmountLimits,
  validateAgainstLimits,
  normalizeRate,
  ratesFromEnv,
  feeFor,
  netFromGross,
  grossUpFor,
  payerCoversFee,
  chargeFor,
};

