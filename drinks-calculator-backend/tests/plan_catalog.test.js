// backend/tests/plan_catalog.test.js
// The catalog decides money and access at the same time, so the tests pin both: the
// agreed 20% annual discount, and — most importantly — that a yearly purchase key can
// never be ranked as a free plan.
const {
  PLAN_CATALOG,
  VALID_PLAN_KEYS,
  getPlan,
  planTier,
  planMonths,
  isYearlyPlan,
  listPlans,
} = require('../utils/planCatalog');

describe('planCatalog', () => {
  test('prices are the agreed 20% annual discount', () => {
    expect(PLAN_CATALOG.starter.amount).toBe(5000);
    expect(PLAN_CATALOG.pro.amount).toBe(15000);
    expect(PLAN_CATALOG.starter_yearly.amount).toBe(48000);
    expect(PLAN_CATALOG.pro_yearly.amount).toBe(144000);
  });

  test('a year costs less than twelve months bought monthly', () => {
    expect(PLAN_CATALOG.starter_yearly.amount).toBeLessThan(
      12 * PLAN_CATALOG.starter.amount
    );
    expect(PLAN_CATALOG.pro_yearly.amount).toBeLessThan(12 * PLAN_CATALOG.pro.amount);
  });

  test('a yearly purchase key maps to its tier, never to free', () => {
    expect(planTier('pro_yearly')).toBe('pro');
    expect(planTier('starter_yearly')).toBe('starter');
    expect(planTier('pro')).toBe('pro');
    expect(planTier('starter')).toBe('starter');
  });

  test('an unknown key is free, not a paid tier', () => {
    expect(planTier('gold')).toBe('free');
    expect(planTier('')).toBe('free');
    expect(planTier(null)).toBe('free');
    expect(planTier(undefined)).toBe('free');
  });

  test('yearly buys twelve months, monthly buys one', () => {
    expect(planMonths('starter_yearly')).toBe(12);
    expect(planMonths('pro_yearly')).toBe(12);
    expect(planMonths('pro')).toBe(1);
    expect(planMonths('nonsense')).toBe(1);
  });

  test('isYearlyPlan distinguishes the periods', () => {
    expect(isYearlyPlan('pro_yearly')).toBe(true);
    expect(isYearlyPlan('starter_yearly')).toBe(true);
    expect(isYearlyPlan('pro')).toBe(false);
    expect(isYearlyPlan('free')).toBe(false);
  });

  test('every key the API validates is a real catalog entry', () => {
    expect(VALID_PLAN_KEYS).toEqual(
      expect.arrayContaining(['starter', 'pro', 'starter_yearly', 'pro_yearly'])
    );
    VALID_PLAN_KEYS.forEach((key) => expect(getPlan(key)).not.toBeNull());
  });

  test('listPlans returns a copy, so the app cannot mutate prices', () => {
    const plans = listPlans();
    plans.pro.amount = 1;
    expect(PLAN_CATALOG.pro.amount).toBe(15000);
    expect(listPlans().pro.amount).toBe(15000);
  });
});
