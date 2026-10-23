// tests/two_factor.test.js
// The second factor guards the accounts that can move money. These tests pin the
// two promises that keep it from becoming a lockout: it is off unless the user
// opted in AND the mailer works, and a code dies after 5 wrong tries or 10 minutes.
const {
  isSecondFactorRole,
  requiresSecondFactor,
  generateOtpCode,
  createChallengeStore,
} = require('../utils/twoFactor');

describe('isSecondFactorRole', () => {
  test.each(['Manager', 'Owner', 'Admin', 'manager', 'owner', 'admin'])(
    '%s must use a second factor',
    (role) => expect(isSecondFactorRole(role)).toBe(true)
  );

  test.each(['Staff', 'Customer', 'Cashier', ''])(
    '%s is not challenged',
    (role) => expect(isSecondFactorRole(role)).toBe(false)
  );

  test('a missing role is never challenged', () => {
    expect(isSecondFactorRole(undefined)).toBe(false);
    expect(isSecondFactorRole(null)).toBe(false);
  });
});

describe('requiresSecondFactor', () => {
  test('a manager who opted in with a working mailer is challenged', () => {
    expect(
      requiresSecondFactor({ enabled: true, role: 'Manager', emailConfigured: true })
    ).toBe(true);
  });

  test('nobody is challenged unless they opted in', () => {
    expect(
      requiresSecondFactor({ enabled: false, role: 'Manager', emailConfigured: true })
    ).toBe(false);
  });

  test('a broken mailer degrades to no second factor instead of no login', () => {
    expect(
      requiresSecondFactor({ enabled: true, role: 'Owner', emailConfigured: false })
    ).toBe(false);
  });

  test('staff who opted in are still not challenged', () => {
    expect(
      requiresSecondFactor({ enabled: true, role: 'Staff', emailConfigured: true })
    ).toBe(false);
  });
});

describe('generateOtpCode', () => {
  test('is always 6 digits, zero-padded', () => {
    for (let i = 0; i < 200; i += 1) {
      expect(generateOtpCode()).toMatch(/^\d{6}$/);
    }
  });

  test('does not repeat itself', () => {
    const codes = new Set();
    for (let i = 0; i < 50; i += 1) codes.add(generateOtpCode());
    expect(codes.size).toBeGreaterThan(40);
  });
});

describe('createChallengeStore', () => {
  const now = 1_000_000;

  test('a fresh code verifies and is consumed', () => {
    const store = createChallengeStore();
    const code = store.create({ userId: 7, now });
    expect(store.check({ userId: 7, code, now })).toEqual({ ok: true, code: 'ok' });
    // A code is never valid twice.
    expect(store.check({ userId: 7, code, now }).ok).toBe(false);
  });

  test('an unknown user has no challenge', () => {
    const store = createChallengeStore();
    expect(store.check({ userId: 7, code: '123456', now }).code).toBe('missing');
  });

  test('a code expires after its TTL', () => {
    const store = createChallengeStore({ ttlMs: 1000 });
    const code = store.create({ userId: 7, now });
    expect(store.check({ userId: 7, code, now: now + 1001 }).code).toBe('expired');
  });

  test('a wrong code counts down the attempts', () => {
    const store = createChallengeStore();
    const code = store.create({ userId: 7, now });
    const wrong = code === '000000' ? '111111' : '000000';
    const first = store.check({ userId: 7, code: wrong, now });
    expect(first.code).toBe('invalid');
    expect(first.attemptsLeft).toBe(4);
  });

  test('five wrong tries burn the challenge — the right code no longer works', () => {
    const store = createChallengeStore();
    const code = store.create({ userId: 7, now });
    const wrong = code === '000000' ? '111111' : '000000';
    for (let i = 0; i < 4; i += 1) {
      expect(store.check({ userId: 7, code: wrong, now }).code).toBe('invalid');
    }
    expect(store.check({ userId: 7, code: wrong, now }).code).toBe('tooManyAttempts');
    expect(store.check({ userId: 7, code, now }).code).toBe('missing');
  });

  test('a malformed code is rejected without spending an attempt', () => {
    const store = createChallengeStore();
    const code = store.create({ userId: 7, now });
    expect(store.check({ userId: 7, code: 'abc', now }).code).toBe('invalid');
    expect(store.check({ userId: 7, code: undefined, now }).code).toBe('invalid');
    expect(store.check({ userId: 7, code, now }).ok).toBe(true);
  });

  test('a new login replaces the previous code', () => {
    const store = createChallengeStore();
    const first = store.create({ userId: 7, now });
    const second = store.create({ userId: 7, now: now + 1 });
    expect(store.size).toBe(1);
    expect(store.check({ userId: 7, code: first, now: now + 2 }).ok).toBe(false);
    expect(store.check({ userId: 7, code: second, now: now + 2 }).ok).toBe(true);
  });

  test('expired entries are pruned, so the store cannot grow forever', () => {
    const store = createChallengeStore({ ttlMs: 1000 });
    for (let id = 1; id <= 20; id += 1) store.create({ userId: id, now });
    expect(store.size).toBe(20);
    store.create({ userId: 99, now: now + 2000 });
    expect(store.size).toBe(1);
  });

  test('the cap is hard: the oldest challenge is dropped', () => {
    const store = createChallengeStore({ ttlMs: 60_000, max: 3 });
    store.create({ userId: 1, now });
    store.create({ userId: 2, now });
    store.create({ userId: 3, now });
    store.create({ userId: 4, now });
    expect(store.size).toBe(3);
    expect(store.check({ userId: 1, code: '123456', now }).code).toBe('missing');
  });

  test('clear() drops a pending challenge', () => {
    const store = createChallengeStore();
    const code = store.create({ userId: 7, now });
    store.clear(7);
    expect(store.check({ userId: 7, code, now }).code).toBe('missing');
  });
});
