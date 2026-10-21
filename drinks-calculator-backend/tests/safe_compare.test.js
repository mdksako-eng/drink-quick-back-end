// tests/safe_compare.test.js
// Guards the platform-admin override: the comparison must be correct, must never
// accept an empty value, and must not be the plain `===` that leaks timing.
const { safeEqual } = require('../utils/safeCompare');

describe('safeEqual', () => {
  test('identical strings match', () => {
    expect(safeEqual('s3cret-value', 's3cret-value')).toBe(true);
  });

  test('different strings do not match', () => {
    expect(safeEqual('s3cret-value', 's3cret-valuf')).toBe(false);
    expect(safeEqual('admin123', 'admin124')).toBe(false);
  });

  test('a prefix does not match', () => {
    expect(safeEqual('admin123', 'admin1234')).toBe(false);
    expect(safeEqual('admin1234', 'admin123')).toBe(false);
  });

  test('empty, null and undefined never match — an unset secret must fail closed', () => {
    expect(safeEqual('', '')).toBe(false);
    expect(safeEqual('', 'admin123')).toBe(false);
    expect(safeEqual(null, 'admin123')).toBe(false);
    expect(safeEqual(undefined, undefined)).toBe(false);
    expect(safeEqual('admin123', null)).toBe(false);
  });

  test('compares by bytes, so multi-byte characters are exact', () => {
    expect(safeEqual('clé-secrète', 'clé-secrète')).toBe(true);
    expect(safeEqual('clé-secrète', 'cle-secrete')).toBe(false);
  });
});
