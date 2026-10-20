// utils/sessionCache.js
// A tiny TTL cache for session lookups.
//
// WHY: every authenticated request used to cost a database round-trip to resolve
// its bearer token (sessionAuth.getSessionUser). On a till that loads several
// endpoints per screen, that is the most repeated query in the whole product.
//
// Safety model: the cache is short lived (default 30 s) and the code that
// REVOKES a session (logout, admin block, lock, new login on another device)
// deletes the entry at the same time — so the staleness window only applies to
// expiries, never to an explicit revocation.
//
// Pure and clock-injectable, so the TTL rule is unit tested rather than trusted.
function createSessionCache({ ttlMs = 30000, maxEntries = 5000, now = () => Date.now() } = {}) {
  const entries = new Map(); // token -> { user, expiresAt }
  const ttl = Number(ttlMs) > 0 ? Number(ttlMs) : 0;
  const limit = Math.max(1, Math.trunc(Number(maxEntries)) || 1);

  function dropExpired() {
    const current = now();
    for (const [token, entry] of entries) {
      if (entry.expiresAt <= current) entries.delete(token);
    }
  }

  return {
    /** Cached user for this token, or null. Never returns a stale entry. */
    get(token) {
      if (!ttl || !token) return null;
      const entry = entries.get(token);
      if (!entry) return null;
      if (entry.expiresAt <= now()) {
        entries.delete(token);
        return null;
      }
      return entry.user;
    },

    set(token, user) {
      if (!ttl || !token || !user) return;
      // Keep the map bounded: Map iterates in insertion order, so the first key is
      // the oldest. This is a cache, not a store — dropping one costs one query.
      if (entries.size >= limit) {
        dropExpired();
        if (entries.size >= limit) entries.delete(entries.keys().next().value);
      }
      entries.set(token, { user, expiresAt: now() + ttl });
    },

    delete(token) {
      if (token) entries.delete(token);
    },

    /** Drop every session of a user (blocked, locked, terminated). */
    deleteForUser(userId) {
      if (userId == null) return;
      for (const [token, entry] of entries) {
        if (String(entry.user?.id) === String(userId)) entries.delete(token);
      }
    },

    clear() {
      entries.clear();
    },

    get size() {
      return entries.size;
    },

    get ttlMs() {
      return ttl;
    },
  };
}

module.exports = { createSessionCache };
