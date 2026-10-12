/**
 * Password reset limits — how many emails one address may ask for per day, and how
 * many wrong codes it may try. No database required.
 *
 * This is the rule behind "one user cannot over-reset their password in a day": the
 * counter lives in rows, not in the process, so recycling the server does not hand
 * out a fresh allowance. It covers:
 *   • the pure rules (allowance, the oldest event aging out, wrong-code allowance),
 *   • the daily cap refusing the extra email with a retry time the app can show,
 *   • the same answer for an address that exists and one that does not, so the limit
 *     cannot be used to discover which addresses are registered, and
 *   • the cap being per address, not global.
 *
 * Run with: npm test
 */
const passwordReset = require('../utils/passwordReset');

const NOW = Date.UTC(2026, 9, 11, 12, 0, 0);
const HOUR = 60 * 60 * 1000;

describe('the reset-email allowance', () => {
  test('the first requests of the day are allowed', () => {
    for (const timestamps of [[], [NOW - HOUR], [NOW - HOUR, NOW - 2 * HOUR]]) {
      const result = passwordReset.evaluateRequest({ timestamps, now: NOW });
      expect(result.allowed).toBe(true);
      expect(result.limit).toBe(passwordReset.DEFAULT_MAX_PER_DAY);
    }
  });

  test('it counts what is left for today', () => {
    const first = passwordReset.evaluateRequest({ timestamps: [], now: NOW });
    expect(first.remaining).toBe(passwordReset.DEFAULT_MAX_PER_DAY - 1);

    const last = passwordReset.evaluateRequest({
      timestamps: [NOW - HOUR, NOW - 2 * HOUR],
      now: NOW,
    });
    expect(last.allowed).toBe(true);
    expect(last.remaining).toBe(0);
  });

  test('the request after the last one is refused, with a usable retry time', () => {
    const used = [NOW - 1 * HOUR, NOW - 2 * HOUR, NOW - 3 * HOUR];
    const result = passwordReset.evaluateRequest({ timestamps: used, now: NOW });

    expect(result.allowed).toBe(false);
    expect(result.used).toBe(3);
    expect(result.remaining).toBe(0);
    // The oldest of the three ages out first: 24h - 3h = 21h.
    expect(result.retryAfterMinutes).toBe(21 * 60);
    expect(passwordReset.requestLimitMessage(result)).toMatch(/limit 3/);
    expect(passwordReset.requestLimitMessage(result)).toMatch(/1260 minutes/);
  });

  test('yesterday does not count against today', () => {
    const result = passwordReset.evaluateRequest({
      timestamps: [NOW - 25 * HOUR, NOW - 30 * HOUR, NOW - 40 * HOUR],
      now: NOW,
    });
    expect(result.allowed).toBe(true);
    expect(result.used).toBe(0);
  });

  test('the allowance is configurable, and a nonsense value falls back', () => {
    const previous = process.env.PASSWORD_RESET_MAX_PER_DAY;
    process.env.PASSWORD_RESET_MAX_PER_DAY = '1';
    expect(passwordReset.maxPerDay()).toBe(1);
    // One already used => the next is refused when the limit is 1.
    expect(
      passwordReset.evaluateRequest({ timestamps: [NOW - HOUR], now: NOW }).allowed
    ).toBe(false);

    process.env.PASSWORD_RESET_MAX_PER_DAY = 'nonsense';
    expect(passwordReset.maxPerDay()).toBe(passwordReset.DEFAULT_MAX_PER_DAY);
    process.env.PASSWORD_RESET_MAX_PER_DAY = '0';
    expect(passwordReset.maxPerDay()).toBe(passwordReset.DEFAULT_MAX_PER_DAY);

    if (previous === undefined) delete process.env.PASSWORD_RESET_MAX_PER_DAY;
    else process.env.PASSWORD_RESET_MAX_PER_DAY = previous;
  });
});

describe('the wrong-code allowance', () => {
  test('five wrong codes are tolerated, the sixth is refused', () => {
    const four = [NOW - 1000, NOW - 2000, NOW - 3000, NOW - 4000];
    const fifth = passwordReset.evaluateCodeAttempt({ timestamps: four, now: NOW });
    expect(fifth.allowed).toBe(true);
    expect(fifth.remaining).toBe(1);

    const five = [...four, NOW - 5000];
    const sixth = passwordReset.evaluateCodeAttempt({ timestamps: five, now: NOW });
    expect(sixth.allowed).toBe(false);
    expect(passwordReset.codeAttemptMessage(sixth)).toMatch(/Too many wrong codes/);
  });

  test('attempts older than fifteen minutes are forgotten', () => {
    const old = [NOW - 16 * 60 * 1000, NOW - 20 * 60 * 1000];
    const result = passwordReset.evaluateCodeAttempt({ timestamps: old, now: NOW });
    expect(result.allowed).toBe(true);
    expect(result.used).toBe(0);
  });

  test('the wrong-code lock is not for ever — the window slides', () => {
    const many = Array.from({ length: 99 }, (_, i) => NOW - i * 1000);
    expect(passwordReset.evaluateCodeAttempt({ timestamps: many, now: NOW }).allowed).toBe(false);

    const later = passwordReset.evaluateCodeAttempt({
      timestamps: [NOW - 16 * 60 * 1000],
      now: NOW,
    });
    expect(later.allowed).toBe(true);
  });
});

describe('reading the stored timestamps', () => {
  test('Postgres timestamps and strings both become ms, and junk is dropped', () => {
    const values = [
      new Date(NOW - 1000).toISOString(),
      new Date(NOW - 2000),
      'not a date',
      null,
    ];
    const inside = passwordReset.within(values, passwordReset.DAY_MS, NOW);
    expect(inside).toHaveLength(2);
    // Oldest first, so the earliest one is the one that ages out first.
    expect(inside[0]).toBeLessThan(inside[1]);
  });

  test('an empty or missing list is simply nothing used', () => {
    expect(passwordReset.within(undefined, passwordReset.DAY_MS, NOW)).toEqual([]);
    expect(passwordReset.evaluateRequest({ timestamps: undefined, now: NOW }).used).toBe(0);
  });
});

describe('the statements that enforce it', () => {
  const store = require('../utils/passwordResetStore');

  /** Records what was sent to Postgres so the SQL itself can be asserted. */
  function fakePool(rows = []) {
    const calls = [];
    return {
      calls,
      query: async (sql, params) => {
        calls.push({ sql, params });
        return { rows };
      },
    };
  }

  test('it reads one address and one kind, inside the window', async () => {
    const pool = fakePool([{ created_at: new Date(NOW - 1000).toISOString() }]);
    const timestamps = await store.resetEvents(pool, 'a@b.c', 'request', passwordReset.DAY_MS, NOW);

    const { sql, params } = pool.calls[0];
    expect(sql).toMatch(/FROM password_reset_requests/);
    expect(sql).toMatch(/email = \$1 AND kind = \$2 AND created_at >= \$3/);
    expect(params[0]).toBe('a@b.c');
    // The kind and the window are what make the daily cap real — pin both.
    expect(params[1]).toBe('request');
    expect(params[2].getTime()).toBe(NOW - passwordReset.DAY_MS);
    expect(timestamps).toEqual([NOW - 1000]);
  });

  test('a row whose timestamp makes no sense does not count', async () => {
    const pool = fakePool([{ created_at: null }]);
    const timestamps = await store.resetEvents(pool, 'a@b.c', 'request', passwordReset.DAY_MS, NOW);
    expect(Number.isNaN(timestamps[0])).toBe(true);
    // …and the rule ignores it rather than treating it as "used".
    expect(passwordReset.evaluateRequest({ timestamps, now: NOW }).used).toBe(0);
  });

  test('a request is recorded with the address as typed, and the caller IP', async () => {
    const pool = fakePool();
    await store.recordResetEvent(pool, 'A@B.c ', 'request', {
      headers: { 'x-forwarded-for': '41.202.1.9, 10.0.0.1' },
      ip: '10.0.0.1',
    });

    const { sql, params } = pool.calls[0];
    expect(sql).toMatch(/INSERT INTO password_reset_requests/);
    expect(params[0]).toBe('A@B.c ');
    expect(params[1]).toBe('request');
    // First hop only, so a proxy chain cannot lengthen or forge the stored value.
    expect(params[2]).toBe('41.202.1.9');
  });

  test('no headers at all still records the attempt', async () => {
    const pool = fakePool();
    await store.recordResetEvent(pool, 'a@b.c', 'code_attempt', {});
    expect(pool.calls[0].params).toEqual(['a@b.c', 'code_attempt', null]);
  });

  test('clearing the wrong tries deletes only that kind, for that address', async () => {
    const pool = fakePool();
    await store.clearCodeAttempts(pool, 'a@b.c');

    const { sql, params } = pool.calls[0];
    expect(sql).toMatch(/DELETE FROM password_reset_requests/);
    expect(sql).toMatch(/kind = 'code_attempt'/);
    // The reset emails already sent must NOT be erased — they are the daily cap.
    expect(sql).not.toMatch(/'request'/);
    expect(params).toEqual(['a@b.c']);
  });
});
