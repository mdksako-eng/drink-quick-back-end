// tests/session_cache.test.js
// The cache exists to remove one database round-trip per authenticated request.
// These tests pin the two things that make it safe: it never returns a stale
// entry, and a revocation can always remove one.
const { createSessionCache } = require('../utils/sessionCache');

function clock(start = 1_000_000) {
  let value = start;
  return {
    now: () => value,
    advance: (ms) => {
      value += ms;
    },
  };
}

const user = { id: 7, username: 'ama', role: 'Staff', company_id: 3, is_active: true };

describe('createSessionCache', () => {
  test('a stored session is returned, then gone after the TTL', () => {
    const c = clock();
    const cache = createSessionCache({ ttlMs: 30000, now: c.now });
    cache.set('tok', user);
    expect(cache.get('tok')).toEqual(user);

    c.advance(29999);
    expect(cache.get('tok')).toEqual(user);

    c.advance(2);
    expect(cache.get('tok')).toBeNull();
    expect(cache.size).toBe(0); // expired entries are dropped, not kept
  });

  test('unknown, empty or missing tokens are misses', () => {
    const cache = createSessionCache({ ttlMs: 30000 });
    expect(cache.get('nope')).toBeNull();
    expect(cache.get('')).toBeNull();
    expect(cache.get(null)).toBeNull();
  });

  test('logout deletes exactly one session', () => {
    const cache = createSessionCache({ ttlMs: 30000 });
    cache.set('a', { ...user, id: 1 });
    cache.set('b', { ...user, id: 2 });
    cache.delete('a');
    expect(cache.get('a')).toBeNull();
    expect(cache.get('b')).not.toBeNull();
    expect(cache.size).toBe(1);
  });

  test('blocking a user drops every session of that user, nobody else', () => {
    const cache = createSessionCache({ ttlMs: 30000 });
    cache.set('a1', { ...user, id: 1 });
    cache.set('a2', { ...user, id: 1 }); // same user, second device
    cache.set('b1', { ...user, id: 2 });
    cache.deleteForUser(1);
    expect(cache.get('a1')).toBeNull();
    expect(cache.get('a2')).toBeNull();
    expect(cache.get('b1')).not.toBeNull();
  });

  test('deleteForUser matches string and number ids', () => {
    const cache = createSessionCache({ ttlMs: 30000 });
    cache.set('tok', { ...user, id: '9' });
    cache.deleteForUser(9);
    expect(cache.get('tok')).toBeNull();
  });

  test('the map stays bounded (oldest entry is evicted first)', () => {
    const cache = createSessionCache({ ttlMs: 60000, maxEntries: 2 });
    cache.set('first', { ...user, id: 1 });
    cache.set('second', { ...user, id: 2 });
    cache.set('third', { ...user, id: 3 });
    expect(cache.size).toBe(2);
    expect(cache.get('first')).toBeNull();
    expect(cache.get('third')).not.toBeNull();
  });

  test('a TTL of 0 (or nonsense) disables caching entirely', () => {
    const off = createSessionCache({ ttlMs: 0 });
    off.set('tok', user);
    expect(off.get('tok')).toBeNull();
    expect(off.size).toBe(0);

    const nonsense = createSessionCache({ ttlMs: 'soon' });
    nonsense.set('tok', user);
    expect(nonsense.get('tok')).toBeNull();
  });

  test('nothing is stored for a null user or token', () => {
    const cache = createSessionCache({ ttlMs: 30000 });
    cache.set(null, user);
    cache.set('tok', null);
    expect(cache.size).toBe(0);
  });

  test('clear() empties it', () => {
    const cache = createSessionCache({ ttlMs: 30000 });
    cache.set('a', user);
    cache.set('b', user);
    cache.clear();
    expect(cache.size).toBe(0);
  });
});
