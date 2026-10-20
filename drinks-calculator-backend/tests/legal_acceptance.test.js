// tests/legal_acceptance.test.js
// Consent must be recorded, and "no" must never register. These tests pin the
// rule the register route follows.
const {
  checkAcceptance, acceptanceRows, legalVersion, acceptanceRequired,
  DOCUMENTS, DEFAULT_VERSION,
} = require('../utils/legalAcceptance');

describe('checkAcceptance', () => {
  test('accepted → proceeds and is recorded', () => {
    expect(checkAcceptance({ accepted: true, required: true }))
      .toEqual({ ok: true, record: true });
    expect(checkAcceptance({ accepted: true, required: false }))
      .toEqual({ ok: true, record: true });
  });

  test('explicitly refused → blocked, whatever the switch says', () => {
    expect(checkAcceptance({ accepted: false, required: false }))
      .toEqual({ ok: false, record: false, code: 'legal_not_accepted' });
    expect(checkAcceptance({ accepted: false, required: true }).ok).toBe(false);
  });

  test('absent (older app) → tolerated but NOT recorded while the switch is off', () => {
    expect(checkAcceptance({ accepted: undefined, required: false }))
      .toEqual({ ok: true, record: false });
  });

  test('absent and required → blocked with a stable code', () => {
    expect(checkAcceptance({ accepted: undefined, required: true }))
      .toEqual({ ok: false, record: false, code: 'legal_acceptance_required' });
  });
});

describe('acceptanceRows', () => {
  test('records both documents with the version and the moment', () => {
    const at = new Date('2026-10-20T10:00:00Z');
    const rows = acceptanceRows({ userId: 42, version: '2026-10', acceptedAt: at, ip: '1.2.3.4' });
    expect(rows).toHaveLength(2);
    expect(rows.map((r) => r.document)).toEqual(DOCUMENTS);
    expect(rows[0]).toEqual({
      user_id: 42, document: 'terms', version: '2026-10', accepted_at: at, ip: '1.2.3.4',
    });
    expect(rows[1].document).toBe('privacy');
  });

  test('falls back to the default version and no ip', () => {
    const rows = acceptanceRows({ userId: 7 });
    expect(rows.every((r) => r.version === DEFAULT_VERSION)).toBe(true);
    expect(rows.every((r) => r.ip === null)).toBe(true);
    expect(rows.every((r) => r.user_id === 7)).toBe(true);
  });
});

describe('environment switches', () => {
  test('LEGAL_VERSION overrides the default, blank falls back', () => {
    expect(legalVersion({ LEGAL_VERSION: '2027-01' })).toBe('2027-01');
    expect(legalVersion({ LEGAL_VERSION: '   ' })).toBe(DEFAULT_VERSION);
    expect(legalVersion({})).toBe(DEFAULT_VERSION);
  });

  test('enforcement is off unless explicitly "true"', () => {
    expect(acceptanceRequired({})).toBe(false);
    expect(acceptanceRequired({ LEGAL_ACCEPTANCE_REQUIRED: 'yes' })).toBe(false);
    expect(acceptanceRequired({ LEGAL_ACCEPTANCE_REQUIRED: 'TRUE' })).toBe(true);
  });
});
