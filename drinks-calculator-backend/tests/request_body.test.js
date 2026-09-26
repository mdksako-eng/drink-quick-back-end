/**
 * The raw request body used to verify webhook HMACs.
 *
 * Covers the rule: signatures are computed over the bytes that were sent, not
 * over a re-serialised object — Express only exposes those bytes via the body
 * parser's `verify` hook, so the fallback is a last resort, never the default.
 *
 * Run with: npm test
 */
const { rawBodyOf } = require('../utils/requestBody');

describe('rawBodyOf', () => {
  test('returns the exact bytes Express captured', () => {
    expect(rawBodyOf({ rawBody: '{"a":  1}' })).toBe('{"a":  1}');
  });

  test('keeps whitespace, so a signed body still verifies', () => {
    const signed = '{\n  "reference": "sub_1",\n  "status": "complete"\n}';
    expect(rawBodyOf({ rawBody: signed, body: JSON.parse(signed) })).toBe(signed);
  });

  test('accepts a Buffer', () => {
    expect(rawBodyOf({ rawBody: Buffer.from('{"a":1}', 'utf8') })).toBe('{"a":1}');
  });

  test('falls back to a re-serialisation when no raw body exists', () => {
    expect(rawBodyOf({ body: { a: 1 } })).toBe('{"a":1}');
  });

  test('an empty raw body falls back rather than returning an empty string', () => {
    expect(rawBodyOf({ rawBody: '', body: { a: 1 } })).toBe('{"a":1}');
    expect(rawBodyOf({ rawBody: Buffer.alloc(0), body: { a: 1 } })).toBe('{"a":1}');
  });

  test('never returns null or undefined', () => {
    [null, undefined, {}, { rawBody: null, body: null }].forEach((req) => {
      expect(rawBodyOf(req)).toBe('{}');
    });
  });
});
