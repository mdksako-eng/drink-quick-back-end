// tests/rate_limiter.test.js
// The limiter guards login and password reset, so its behaviour must not drift:
// `max` attempts per window per key, the next one refused, and no unbounded growth.
const { createRateLimiter } = require('../utils/rateLimiter');

function clock(start = 1_000_000) {
  let value = start;
  return {
    now: () => value,
    advance: (ms) => {
      value += ms;
    },
  };
}

describe('createRateLimiter', () => {
  test('allows exactly `max` attempts, then refuses (same as before)', () => {
    const limiter = createRateLimiter({ max: 3, windowMs: 1000 });
    expect(limiter.check('k')).toBe(true);
    expect(limiter.check('k')).toBe(true);
    expect(limiter.check('k')).toBe(true);
    expect(limiter.check('k')).toBe(false);
    expect(limiter.check('k')).toBe(false);
  });

  test('the window resets after windowMs', () => {
    const c = clock();
    const limiter = createRateLimiter({ max: 2, windowMs: 1000, now: c.now });
    limiter.check('k');
    limiter.check('k');
    expect(limiter.check('k')).toBe(false);

    c.advance(999);
    expect(limiter.check('k')).toBe(false);

    c.advance(2);
    expect(limiter.check('k')).toBe(true); // fresh window
  });

  test('keys are independent (one flood does not block another account)', () => {
    const limiter = createRateLimiter({ max: 2, windowMs: 1000 });
    limiter.check('a');
    limiter.check('a');
    expect(limiter.check('a')).toBe(false);
    expect(limiter.check('b')).toBe(true);
  });

  test('remaining() reflects the window, and reset() clears it', () => {
    const limiter = createRateLimiter({ max: 5, windowMs: 1000 });
    expect(limiter.remaining('k')).toBe(5);
    limiter.check('k');
    limiter.check('k');
    expect(limiter.remaining('k')).toBe(3);
    limiter.reset('k');
    expect(limiter.remaining('k')).toBe(5);
  });

  test('expired keys are pruned, so memory cannot grow forever', () => {
    const c = clock();
    const limiter = createRateLimiter({ max: 1, windowMs: 1000, now: c.now, maxKeys: 3 });
    limiter.check('a');
    limiter.check('b');
    limiter.check('c');
    expect(limiter.size).toBe(3);

    c.advance(1500); // all three expire
    limiter.check('d'); // hitting the cap triggers the sweep
    expect(limiter.size).toBeLessThanOrEqual(3);
    expect(limiter.remaining('d')).toBe(0); // max 1, one attempt already used
    expect(limiter.check('d')).toBe(false); // the new key still counts normally
  });

  test('a missing key never blocks (caller could not build one)', () => {
    const limiter = createRateLimiter({ max: 1, windowMs: 1000 });
    for (let i = 0; i < 10; i += 1) expect(limiter.check('')).toBe(true);
    expect(limiter.check(null)).toBe(true);
    expect(limiter.check(undefined)).toBe(true);
  });

  test('bad configuration falls back to sane values', () => {
    // A 1 ms window would make this test race the clock, so the window clamp is
    // asserted separately from the attempt behaviour.
    const limiter = createRateLimiter({ max: 0, windowMs: 60000 });
    expect(limiter.max).toBe(1);
    expect(limiter.check('k')).toBe(true);
    expect(limiter.check('k')).toBe(false);

    const badWindow = createRateLimiter({ max: 5, windowMs: -5 });
    expect(badWindow.windowMs).toBeGreaterThan(0);
    const badMax = createRateLimiter({ max: 'nonsense', windowMs: 60000 });
    expect(badMax.max).toBe(1);
  });
});
