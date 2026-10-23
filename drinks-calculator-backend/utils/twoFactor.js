// utils/twoFactor.js
//
// 🔐 Second factor for the accounts that can move money and change settings:
// Manager, Owner and the platform Admin. Staff and Customer logins are untouched.
//
// Two rules shape everything here:
//   1. **Off by default.** A user is challenged only when they turned it on AND the
//      mailer is configured. A deploy can therefore never lock anyone out, and a
//      broken mailer degrades to "no second factor" instead of "no login".
//   2. **One challenge at a time, bounded.** Challenges live in a capped, self-pruning
//      in-memory store (same discipline as utils/rateLimiter.js) — an unauthenticated
//      caller cannot grow the process by asking for codes.
//
// The verification compares codes in constant time (utils/safeCompare.js) and counts
// wrong tries, so a 6-digit code cannot be brute-forced inside its lifetime.

const crypto = require('crypto');
const { safeEqual } = require('./safeCompare');

const DEFAULT_TTL_MS = 10 * 60 * 1000; // 10 minutes
const MAX_ATTEMPTS = 5;
const MAX_CHALLENGES = 500;

/// Roles that must use a second factor when they opt in.
const SECOND_FACTOR_ROLES = ['Manager', 'Owner', 'Admin', 'manager', 'owner', 'admin'];

function isSecondFactorRole(role) {
  if (!role) return false;
  return SECOND_FACTOR_ROLES.includes(String(role).trim());
}

/// Does this login need a code right now?
///
/// `emailConfigured` is the safety valve: with no mailer we cannot deliver a code,
/// so demanding one would lock the user out. It also means the feature silently
/// turns itself off on a misconfigured deploy instead of blocking every manager.
function requiresSecondFactor({ enabled, role, emailConfigured }) {
  if (!enabled) return false;
  if (!emailConfigured) return false;
  return isSecondFactorRole(role);
}

/// 6 digits, uniformly distributed, from the CSPRNG (never Math.random).
function generateOtpCode() {
  return String(crypto.randomInt(0, 1000000)).padStart(6, '0');
}

/// Capped, self-pruning store of pending challenges.
///
/// Keyed by user id: a second login for the same user replaces the first code
/// instead of leaving two valid codes alive. `now` is injectable so tests need no
/// timers.
function createChallengeStore({ ttlMs = DEFAULT_TTL_MS, max = MAX_CHALLENGES } = {}) {
  const challenges = new Map();

  function prune(now) {
    for (const [key, entry] of challenges) {
      if (entry.expiresAt <= now) challenges.delete(key);
    }
  }

  return {
    /// Creates (or replaces) the challenge for `userId` and returns its code.
    create({ userId, now = Date.now() }) {
      prune(now);
      // Still full after pruning → drop the oldest, so the cap is a hard cap.
      while (challenges.size >= max) {
        const oldest = challenges.keys().next().value;
        challenges.delete(oldest);
      }
      const code = generateOtpCode();
      challenges.set(String(userId), {
        code,
        attempts: 0,
        createdAt: now,
        expiresAt: now + ttlMs,
      });
      return code;
    },

    /// Checks a submitted code. Returns the reason on failure so the route can
    /// answer honestly ("ask for a new code" vs "wrong code, N tries left").
    check({ userId, code, now = Date.now() }) {
      const key = String(userId);
      const entry = challenges.get(key);
      if (!entry) return { ok: false, code: 'missing' };
      if (entry.expiresAt <= now) {
        challenges.delete(key);
        return { ok: false, code: 'expired' };
      }
      if (typeof code !== 'string' || code.length !== 6) {
        return { ok: false, code: 'invalid', attemptsLeft: MAX_ATTEMPTS - entry.attempts };
      }
      if (!safeEqual(code, entry.code)) {
        entry.attempts += 1;
        if (entry.attempts >= MAX_ATTEMPTS) {
          // Burn the challenge: a guesser must ask for a fresh code, which the
          // per-account rate limiter already caps.
          challenges.delete(key);
          return { ok: false, code: 'tooManyAttempts' };
        }
        return { ok: false, code: 'invalid', attemptsLeft: MAX_ATTEMPTS - entry.attempts };
      }
      // Success consumes the challenge — a code is never valid twice.
      challenges.delete(key);
      return { ok: true, code: 'ok' };
    },

    /// Used by the settings endpoint to drop a pending challenge.
    clear(userId) {
      challenges.delete(String(userId));
    },

    get size() {
      return challenges.size;
    },
  };
}

module.exports = {
  SECOND_FACTOR_ROLES,
  DEFAULT_TTL_MS,
  MAX_ATTEMPTS,
  isSecondFactorRole,
  requiresSecondFactor,
  generateOtpCode,
  createChallengeStore,
};
