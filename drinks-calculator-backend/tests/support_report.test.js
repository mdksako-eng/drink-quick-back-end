// backend/tests/support_report.test.js
// The rules that make a bug report or complaint usable: a real message, a bounded
// context, and text that cannot inject HTML into the email support receives.
const {
  CATEGORIES,
  CONTEXT_KEYS,
  MAX_MESSAGE,
  MIN_MESSAGE,
  normalizeCategory,
  cleanText,
  validateReport,
  defaultSubject,
  sanitizeContext,
  escapeHtml,
  newReference,
  buildEmail,
} = require('../utils/supportReport');

describe('categories', () => {
  test('accepts the four documented categories', () => {
    expect(normalizeCategory('bug')).toBe('bug');
    expect(normalizeCategory('COMPLAINT')).toBe('complaint');
    expect(normalizeCategory(' idea ')).toBe('idea');
    expect(normalizeCategory('other')).toBe('other');
  });

  test('anything else becomes other, never a crash', () => {
    expect(normalizeCategory('nonsense')).toBe(CATEGORIES.OTHER);
    expect(normalizeCategory('')).toBe(CATEGORIES.OTHER);
    expect(normalizeCategory(null)).toBe(CATEGORIES.OTHER);
    expect(normalizeCategory(undefined)).toBe(CATEGORIES.OTHER);
  });

  test('each category has a default subject support can scan', () => {
    expect(defaultSubject('bug')).toBe('Bug report');
    expect(defaultSubject('complaint')).toBe('Complaint');
    expect(defaultSubject('idea')).toBe('Suggestion');
    expect(defaultSubject('other')).toBe('Support request');
    expect(defaultSubject('nonsense')).toBe('Support request');
  });
});

describe('validateReport', () => {
  test('accepts a real message and trims it', () => {
    const result = validateReport({ category: 'bug', message: '  The till froze on save  ' });
    expect(result.ok).toBe(true);
    expect(result.value.message).toBe('The till froze on save');
    expect(result.value.category).toBe('bug');
    expect(result.value.subject).toBe('Bug report');
  });

  test('uses the subject the user typed when there is one', () => {
    const result = validateReport({
      category: 'bug', subject: 'Stock count wrong', message: 'Ten digits over',
    });
    expect(result.value.subject).toBe('Stock count wrong');
  });

  test('refuses an empty or too-short message', () => {
    expect(validateReport({ message: '' }).reason).toBe('message_required');
    expect(validateReport({ message: '   ' }).reason).toBe('message_required');
    expect(validateReport({ message: 'nope' }).reason).toBe('message_too_short');
    expect(validateReport({ message: 'a'.repeat(MIN_MESSAGE - 1) }).reason).toBe('message_too_short');
  });

  test('refuses an oversized message rather than storing a novel', () => {
    expect(validateReport({ message: 'a'.repeat(MAX_MESSAGE + 1) }).reason).toBe('message_too_long');
    expect(validateReport({ message: 'a'.repeat(MAX_MESSAGE) }).ok).toBe(true);
  });

  test('an unknown category still produces a valid report', () => {
    const result = validateReport({ category: 'something', message: 'The app closed on login' });
    expect(result.ok).toBe(true);
    expect(result.value.category).toBe('other');
  });
});

describe('cleanText', () => {
  test('collapses newlines and runs of spaces', () => {
    expect(cleanText('  hello   world \n\n  again ')).toBe('hello world again');
    expect(cleanText(null)).toBe('');
    expect(cleanText(undefined)).toBe('');
  });
});

describe('sanitizeContext', () => {
  test('keeps only the whitelisted keys', () => {
    const context = sanitizeContext({
      platform: 'android',
      appVersion: '2.0.1',
      screen: 'calculator',
      secret: 'should not be here',
    });
    expect(context).toEqual({ platform: 'android', appVersion: '2.0.1', screen: 'calculator' });
    expect(Object.keys(context).every((key) => CONTEXT_KEYS.includes(key))).toBe(true);
  });

  test('bounds each value and drops empty ones', () => {
    const context = sanitizeContext({ platform: 'x'.repeat(500), screen: '   ', deviceId: 'abc' });
    expect(context.platform).toHaveLength(120);
    expect(context.screen).toBeUndefined();
    expect(context.deviceId).toBe('abc');
  });

  test('survives junk input', () => {
    expect(sanitizeContext(null)).toEqual({});
    expect(sanitizeContext('not an object')).toEqual({});
    expect(sanitizeContext(undefined)).toEqual({});
  });
});

describe('escapeHtml', () => {
  test('neutralises a payload instead of shipping it', () => {
    const escaped = escapeHtml('<script>alert("x")</script>');
    expect(escaped).not.toContain('<script>');
    expect(escaped).toContain('&lt;script&gt;');
    expect(escaped).toContain('&quot;');
  });

  test('handles empty and null', () => {
    expect(escapeHtml('')).toBe('');
    expect(escapeHtml(null)).toBe('');
  });
});

describe('newReference', () => {
  test('is traceable and names the company and category', () => {
    const ref = newReference(42, 'bug', 1791411290905, () => 0.5);
    expect(ref).toMatch(/^sup_42_bug_1791411290905_[0-9a-f]{6}$/);
  });

  test('copes with an unknown company and a junk category', () => {
    expect(newReference(null, 'nonsense', 1, () => 0)).toMatch(/^sup_na_other_1_/);
  });

  test('differs between two reports in the same millisecond', () => {
    const a = newReference(1, 'bug', 5, () => 0.1);
    const b = newReference(1, 'bug', 5, () => 0.9);
    expect(a).not.toBe(b);
  });
});

describe('buildEmail', () => {
  const report = { category: 'complaint', subject: 'Cold beer served warm', message: 'Twice tonight.' };

  test('carries the reference, the sender and the message', () => {
    const { subject, text } = buildEmail({
      report,
      user: { username: 'onean', email: 'onean@example.com', phone: '+237690000000' },
      companyName: 'Banga school Gold',
      context: { platform: 'android', appVersion: '2.0.1', screen: 'calculator' },
      reference: 'sup_42_complaint_1_abcdef',
    });
    expect(subject).toContain('[complaint]');
    expect(subject).toContain('onean @ Banga school Gold');
    expect(text).toContain('sup_42_complaint_1_abcdef');
    expect(text).toContain('Twice tonight.');
    expect(text).toContain('platform: android');
    expect(text).toContain('screen: calculator');
  });

  test('never emits the raw user text as HTML', () => {
    const { html } = buildEmail({
      report: { category: 'bug', subject: 'X', message: '<img src=x onerror=alert(1)>' },
      user: { username: 'u' },
      reference: 'r',
    });
    expect(html).not.toContain('<img');
    expect(html).toContain('&lt;img');
  });

  test('is safe with almost no input', () => {
    const { subject, text } = buildEmail({});
    expect(subject).toContain('[other]');
    expect(text).toContain('Reference:');
  });
});

