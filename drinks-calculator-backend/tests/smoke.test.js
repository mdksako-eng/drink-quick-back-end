/**
 * Smoke tests — no database required.
 * Run with: npm test
 */
const bcrypt = require('bcryptjs');

describe('password hashing helpers', () => {
  const isBcryptHash = (stored) =>
    typeof stored === 'string' && stored.startsWith('$2');

  test('bcrypt hash round-trips correctly', async () => {
    const hash = await bcrypt.hash('far123', 10);
    expect(hash.startsWith('$2')).toBe(true);
    expect(await bcrypt.compare('far123', hash)).toBe(true);
    expect(await bcrypt.compare('wrong', hash)).toBe(false);
  });

  test('isBcryptHash detects bcrypt hashes but not plaintext', () => {
    expect(isBcryptHash('$2b$10$abcdefghijklmnopqrstuv')).toBe(true);
    expect(isBcryptHash('$2a$10$abcdefghijklmnopqrstuv')).toBe(true);
    expect(isBcryptHash('far123')).toBe(false);
    expect(isBcryptHash(null)).toBe(false);
    expect(isBcryptHash('')).toBe(false);
  });
});