/**
 * Who owns the company — the flag the app gates owner-only actions on
 * (change the company logo, branding, clear company data).
 *
 * The regression this guards: `isOwner` used to be computed only at login, so
 * GET /auth/me (called on every app start) returned nothing and the real owner
 * was treated as a plain manager — they could not change the logo.
 *
 * Run with: npm test
 */
const { ownsCompanyRow, resolveIsOwner } = require('../utils/companyOwner');

/** A db stub that answers the two queries the helper makes. */
function fakeDb({ ownerId = null, claimSucceeds = true, fail = false } = {}) {
  const calls = [];
  return {
    calls,
    async query(sql, params) {
      calls.push({ sql, params });
      if (fail) throw new Error('database down');
      if (/^\s*SELECT/i.test(sql)) return { rows: [{ owner_id: ownerId }] };
      return { rows: claimSucceeds ? [{ owner_id: params[0] }] : [] };
    },
  };
}

describe('ownsCompanyRow', () => {
  test('the owner id matching the user is the owner', () => {
    expect(ownsCompanyRow({ owner_id: 7 }, 7)).toBe(true);
    expect(ownsCompanyRow({ owner_id: '7' }, 7)).toBe(true);
  });

  test('someone else is not the owner', () => {
    expect(ownsCompanyRow({ owner_id: 7 }, 8)).toBe(false);
  });

  test('an unowned company belongs to nobody yet', () => {
    expect(ownsCompanyRow({ owner_id: null }, 7)).toBe(false);
    expect(ownsCompanyRow({}, 7)).toBe(false);
    expect(ownsCompanyRow(null, 7)).toBe(false);
    expect(ownsCompanyRow({ owner_id: 7 }, null)).toBe(false);
  });
});

describe('resolveIsOwner', () => {
  test('the company owner is recognised', async () => {
    const db = fakeDb({ ownerId: 7 });
    expect(await resolveIsOwner(db, { id: 7, company_id: 1, role: 'Manager' })).toBe(true);
    expect(db.calls.length).toBe(1); // just the lookup, no claim
  });

  test('a co-manager is not the owner', async () => {
    const db = fakeDb({ ownerId: 7 });
    expect(await resolveIsOwner(db, { id: 9, company_id: 1, role: 'Manager' })).toBe(false);
  });

  test('the first manager claims a company that has no owner (self-heal)', async () => {
    const db = fakeDb({ ownerId: null });
    expect(await resolveIsOwner(db, { id: 5, company_id: 1, role: 'Manager' })).toBe(true);
    expect(db.calls.some((c) => /UPDATE companies SET owner_id/i.test(c.sql))).toBe(true);
  });

  test('staff never claim an unowned company', async () => {
    const db = fakeDb({ ownerId: null });
    expect(await resolveIsOwner(db, { id: 5, company_id: 1, role: 'Staff' })).toBe(false);
    expect(db.calls.some((c) => /UPDATE/i.test(c.sql))).toBe(false);
  });

  test('a lost race to claim is not ownership', async () => {
    const db = fakeDb({ ownerId: null, claimSucceeds: false });
    expect(await resolveIsOwner(db, { id: 5, company_id: 1, role: 'Manager' })).toBe(false);
  });

  test('camelCase fields work too (the model returns either shape)', async () => {
    const db = fakeDb({ ownerId: 7 });
    expect(await resolveIsOwner(db, { _id: 7, companyId: 1, role: 'Manager' })).toBe(true);
  });

  test('a missing company or user is simply not an owner', async () => {
    expect(await resolveIsOwner(fakeDb(), { id: 7, role: 'Manager' })).toBe(false);
    expect(await resolveIsOwner(fakeDb(), { company_id: 1, role: 'Manager' })).toBe(false);
    expect(await resolveIsOwner(null, { id: 7, company_id: 1 })).toBe(false);
    expect(await resolveIsOwner(fakeDb(), null)).toBe(false);
  });

  test('a database failure is never an ownership claim, and never throws', async () => {
    const db = fakeDb({ fail: true });
    expect(await resolveIsOwner(db, { id: 7, company_id: 1, role: 'Manager' })).toBe(false);
  });
});
