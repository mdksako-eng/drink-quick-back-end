// backend/utils/planCatalog.js
// The single source of truth for what a company can buy.
//
// WHY THIS FILE EXISTS: `companies.plan` is ranked by middleware/planAuth.js, and an
// unknown name ranks as 0 (= free). So storing the PURCHASE KEY 'pro_yearly' in that
// column would silently downgrade a bar that had just paid for a whole year of Pro.
// This module keeps the two concepts apart and is the only place that maps them:
//
//   purchase key   'pro_yearly'   what was bought   — stored on the subscriptions row
//   tier           'pro'          what is unlocked — stored on the company
//   period         'yearly'       how long access runs (1 vs 12 months)
//
// Buying a tier and buying a duration are therefore independent choices, and every
// existing 'starter'/'pro' gate in the app and the API keeps working untouched.
//
// Prices are in XAF and overridable by env, so a price change needs no deploy.

const envInt = (name, fallback) => {
  const parsed = parseInt(process.env[name] || '', 10);
  return Number.isFinite(parsed) && parsed > 0 ? parsed : fallback;
};

// Yearly is 20% off twelve months: 5,000 x 12 = 60,000 -> 48,000, and
// 15,000 x 12 = 180,000 -> 144,000.
const PLAN_CATALOG = {
  starter: {
    amount: envInt('STARTER_PRICE_XAF', 5000),
    currency: 'XAF',
    label: 'Starter',
    tier: 'starter',
    months: 1,
    period: 'monthly',
  },
  starter_yearly: {
    amount: envInt('STARTER_YEARLY_XAF', 48000),
    currency: 'XAF',
    label: 'Starter',
    tier: 'starter',
    months: 12,
    period: 'yearly',
  },
  pro: {
    amount: envInt('PRO_PRICE_XAF', 15000),
    currency: 'XAF',
    label: 'Pro',
    tier: 'pro',
    months: 1,
    period: 'monthly',
  },
  pro_yearly: {
    amount: envInt('PRO_YEARLY_XAF', 144000),
    currency: 'XAF',
    label: 'Pro',
    tier: 'pro',
    months: 12,
    period: 'yearly',
  },
};

const VALID_PLAN_KEYS = Object.keys(PLAN_CATALOG);

/** The catalog entry for a purchase key, or null if the key is unknown. */
const getPlan = (plan) => PLAN_CATALOG[plan] || null;

/**
 * The tier a purchase key unlocks: 'pro_yearly' -> 'pro'.
 * Anything unknown (including 'free' and null) maps to 'free', never to a paid tier.
 */
const planTier = (plan) => (PLAN_CATALOG[plan] ? PLAN_CATALOG[plan].tier : 'free');

/** Months of access a purchase key buys: 'starter_yearly' -> 12. Defaults to 1. */
const planMonths = (plan) => (PLAN_CATALOG[plan] ? PLAN_CATALOG[plan].months : 1);

/** True when the key is an annual purchase. */
const isYearlyPlan = (plan) =>
  Boolean(PLAN_CATALOG[plan]) && PLAN_CATALOG[plan].period === 'yearly';

/** The plan list the app renders (a copy, so callers cannot mutate the catalog). */
const listPlans = () => JSON.parse(JSON.stringify(PLAN_CATALOG));

module.exports = {
  PLAN_CATALOG,
  VALID_PLAN_KEYS,
  getPlan,
  planTier,
  planMonths,
  isYearlyPlan,
  listPlans,
};
