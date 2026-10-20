// utils/rateLimiter.js
// In-memory attempt limiter (login, password reset).
//
// WHY A MODULE: the rule was inline in server.js, and its Map was never pruned —
// every key ever seen stayed for the process's lifetime, so a long-running server
// leaked memory slowly under credential stuffing (exactly when it is under load).
//
// Behaviour kept from the previous implementation: the (max + 1)th attempt inside
// the window is refused, so callers can keep using it as a boolean.
// Pure and clock-injectable, so the window rule is unit tested.
function createRateLimiter({
  max = 10,
  windowMs = 15 * 60 * 1000,
  now = () => Date.now(),
  maxKeys = 50000,
} = {}) {
  const buckets = new Map(); // key -> { count, resetAt }
  const limit = Math.max(1, Math.trunc(Number(max)) || 1);
  const window = Math.max(1, Number(windowMs) || 1);
  const cap = Math.max(1, Math.trunc(Number(maxKeys)) || 1);

  function dropExpired(current) {
    for (const [key, entry] of buckets) {
      if (entry.resetAt <= current) buckets.delete(key);
    }
  }

  return {
    /** Count one attempt for [key]. True while the key is still allowed. */
    check(key) {
      if (!key) return true; // never block a caller that could not build a key
      const current = now();
      const entry = buckets.get(key);
      if (!entry || entry.resetAt <= current) {
        // Only sweep when the map is growing: this is a hot path.
        if (buckets.size >= cap) dropExpired(current);
        buckets.set(key, { count: 1, resetAt: current + window });
        return true;
      }
      entry.count += 1;
      return entry.count <= limit;
    },

    /** Attempts left in the current window (0 once blocked). */
    remaining(key) {
      const entry = buckets.get(key);
      if (!entry || entry.resetAt <= now()) return limit;
      return Math.max(0, limit - entry.count);
    },

    /** Forget a key (e.g. after a successful login). */
    reset(key) {
      if (key) buckets.delete(key);
    },

    get size() {
      return buckets.size;
    },

    get max() {
      return limit;
    },

    get windowMs() {
      return window;
    },
  };
}

module.exports = { createRateLimiter };
