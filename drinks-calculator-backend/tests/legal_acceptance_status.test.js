// tests/legal_acceptance_status.test.js
// The legal gate asks again when the text changes or when an account never saw it
// (manager-created staff). Both cases reduce to: has this user accepted the CURRENT
// version of EVERY document?
const {
  hasAcceptedCurrentVersion,
  DEFAULT_VERSION,
} = require('../utils/legalAcceptance');

const rowsFor = (version) => ([
  { document: 'terms', version },
  { document: 'privacy', version },
]);

describe('hasAcceptedCurrentVersion', () => {
  test('both documents at the current version → accepted', () => {
    expect(hasAcceptedCurrentVersion(rowsFor(DEFAULT_VERSION), DEFAULT_VERSION)).toBe(true);
  });

  test('an account that never accepted (manager-created staff) → not accepted', () => {
    expect(hasAcceptedCurrentVersion([], DEFAULT_VERSION)).toBe(false);
    expect(hasAcceptedCurrentVersion(null, DEFAULT_VERSION)).toBe(false);
  });

  test('only one document → not accepted', () => {
    expect(hasAcceptedCurrentVersion(
      [{ document: 'terms', version: DEFAULT_VERSION }], DEFAULT_VERSION)).toBe(false);
  });

  test('an older version → asked again after the text changes', () => {
    expect(hasAcceptedCurrentVersion(rowsFor('2020-01'), DEFAULT_VERSION)).toBe(false);
  });

  test('a newer version does not satisfy the current one', () => {
    expect(hasAcceptedCurrentVersion(rowsFor('2099-01'), DEFAULT_VERSION)).toBe(false);
  });

  test('a history with the current pair among older rows is accepted', () => {
    const rows = [
      ...rowsFor('2020-01'),
      ...rowsFor(DEFAULT_VERSION),
    ];
    expect(hasAcceptedCurrentVersion(rows, DEFAULT_VERSION)).toBe(true);
  });

  test('an empty or missing version is never satisfied', () => {
    expect(hasAcceptedCurrentVersion(rowsFor(''), '')).toBe(false);
    expect(hasAcceptedCurrentVersion(rowsFor(DEFAULT_VERSION), null)).toBe(false);
  });
});
