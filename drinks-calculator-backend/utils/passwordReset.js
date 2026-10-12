// utils/passwordReset.js
// How often one address may ask for a password-reset email, and how many wrong
// codes it may try. Pure — no Express, no DB — so every rule below is unit tested;
// the routes only hand it the timestamps they read and act on the verdict.
//
// Why a DAILY cap and not just the burst limiter that was already there: this
// endpoint sends mail to an address the caller chooses, so with no daily ceiling it
// is a mail relay pointed at someone else's inbox. The old limiter was in memory
// (10 per 15 minutes), which a restart — or a second instance — simply forgot.
// This one counts rows, so it cannot be reset by recycling the server.
//
// Both limits are checked the same way for an address that exists and one that does
// not. A limit that only fires for real accounts would hand an attacker a way to
// find out which addresses are registered.

const DAY_MS = 24 * 60 * 60 * 1000;
const CODE_ATTEMPT_WINDOW_MS = 15 * 60 * 1000;

const DEFAULT_MAX_PER_DAY = 3;
const DEFAULT_MAX_CODE_ATTEMPTS = 5;

/** A positive whole number from the environment, or the fallback. */
function intFromEnv(value, fallback) {
  const parsed = parseInt(value, 10);
  return Number.isFinite(parsed) && parsed > 0 ? parsed : fallback;
}

/** Reset emails allowed per address per rolling 24 hours (default 3). */
function maxPerDay() {
  return intFromEnv(process.env.PASSWORD_RESET_MAX_PER_DAY, DEFAULT_MAX_PER_DAY);
}

/** Wrong reset codes allowed per address per 15 minutes (default 5). */
function maxCodeAttempts() {
  return intFromEnv(
    process.env.PASSWORD_RESET_MAX_CODE_ATTEMPTS,
    DEFAULT_MAX_CODE_ATTEMPTS
  );
}

/** The timestamps (ms) that fall inside the window, oldest first. */
function within(timestamps, windowMs, now = Date.now()) {
  return (timestamps || [])
    // Accepts a Date, an ISO string or a number: the store hands over ms, but a
    // caller reading a raw row should not have to remember that.
    .map((value) => {
      if (value instanceof Date) return value.getTime();
      if (typeof value === 'string') return Date.parse(value);
      return Number(value);
    })
    .filter((value) => Number.isFinite(value) && value > now - windowMs)
    .sort((a, b) => a - b);
}

/**
 * May this address be sent another reset email?
 *
 * `used` counts what is already in the window, so the request being made now is the
 * one that gets refused once the limit is reached. `retryAfterMinutes` is when the
 * OLDEST one ages out — that is the soonest the address can be served again.
 */
function evaluateRequest({ timestamps, now = Date.now(), limit = maxPerDay() } = {}) {
  const recent = within(timestamps, DAY_MS, now);
  const used = recent.length;
  if (used < limit) {
    return {
      allowed: true,
      limit,
      used,
      remaining: Math.max(0, limit - used - 1),
      retryAfterMinutes: 0,
    };
  }
  const retryAfterMs = Math.max(1000, recent[0] + DAY_MS - now);
  return {
    allowed: false,
    limit,
    used,
    remaining: 0,
    retryAfterMs,
    retryAfterMinutes: Math.ceil(retryAfterMs / 60000),
  };
}

/**
 * May this address try another code?
 *
 * A 6-digit code with unlimited guesses is a guessing game an attacker wins; the
 * wrong ones are counted, and a correct one clears them (see the route).
 */
function evaluateCodeAttempt({ timestamps, now = Date.now(), limit = maxCodeAttempts() } = {}) {
  const recent = within(timestamps, CODE_ATTEMPT_WINDOW_MS, now);
  const used = recent.length;
  if (used < limit) {
    return { allowed: true, limit, used, remaining: Math.max(0, limit - used) };
  }
  return {
    allowed: false,
    limit,
    used,
    remaining: 0,
    retryAfterMs: Math.max(1000, recent[0] + CODE_ATTEMPT_WINDOW_MS - now),
  };
}

/** What the app shows for a refused reset email request. */
function requestLimitMessage(result) {
  const minutes = Math.max(1, result.retryAfterMinutes || 1);
  return `Too many password reset emails for this address today (limit ${result.limit}). Try again in ${minutes} minute${minutes === 1 ? '' : 's'}.`;
}

/** What the app shows once the wrong-code allowance is spent. */
function codeAttemptMessage(result) {
  const minutes = Math.max(1, Math.ceil((result.retryAfterMs || 0) / 60000));
  return `Too many wrong codes. Try again in ${minutes} minute${minutes === 1 ? '' : 's'}.`;
}

module.exports = {
  DAY_MS,
  CODE_ATTEMPT_WINDOW_MS,
  DEFAULT_MAX_PER_DAY,
  DEFAULT_MAX_CODE_ATTEMPTS,
  intFromEnv,
  maxPerDay,
  maxCodeAttempts,
  within,
  evaluateRequest,
  evaluateCodeAttempt,
  requestLimitMessage,
  codeAttemptMessage,
};
