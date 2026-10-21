// utils/safeCompare.js
// Constant-time string comparison for secrets.
//
// WHY: `token === ADMIN_PASSWORD` (and the X-Admin-Password header check) leak
// information through timing: a longer matching prefix takes measurably longer, so
// an attacker can recover the secret one character at a time. crypto.timingSafeEqual
// removes that signal — but it throws on length mismatch, hence this wrapper.
const crypto = require('crypto');

/**
 * Compare two secrets without leaking where they differ.
 * @returns {boolean} true only when both are non-empty and byte-identical
 */
function safeEqual(a, b) {
  const left = Buffer.from(String(a ?? ''), 'utf8');
  const right = Buffer.from(String(b ?? ''), 'utf8');
  if (left.length === 0 || right.length === 0) return false;
  if (left.length !== right.length) return false;
  return crypto.timingSafeEqual(left, right);
}

module.exports = { safeEqual };
