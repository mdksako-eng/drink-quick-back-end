// utils/passwordResetStore.js
// The DB side of the password-reset limits: read the recent events for one address,
// record a new one, clear the wrong-code ones. The pool is passed in (never
// required) so the statements can be tested with a stub — the SQL here IS the
// enforcement (a wrong kind or window would silently disable the cap).

/** Timestamps (ms) of one address's events of a kind, inside the window. */
async function resetEvents(pool, email, kind, windowMs, now = Date.now()) {
  const since = new Date(now - windowMs);
  const result = await pool.query(
    `SELECT created_at FROM password_reset_requests
      WHERE email = $1 AND kind = $2 AND created_at >= $3`,
    [email, kind, since]
  );
  // A row without a usable timestamp becomes NaN on purpose: the rules drop it, so a
  // missing value can never count as a request the user did not make.
  return (result.rows || []).map((row) =>
    row && row.created_at != null ? new Date(row.created_at).getTime() : NaN
  );
}

/** One row per reset email asked for (kind 'request') or wrong code tried. */
async function recordResetEvent(pool, email, kind, req) {
  const forwarded = req && req.headers ? req.headers['x-forwarded-for'] : null;
  const ip = (forwarded || (req && req.ip) || '')
    .toString()
    .split(',')[0]
    .trim()
    .slice(0, 60);
  await pool.query(
    `INSERT INTO password_reset_requests (email, kind, ip) VALUES ($1, $2, $3)`,
    [email, kind, ip || null]
  );
}

/**
 * Forgets the wrong tries for an address.
 *
 * Called when the right code finally arrives: an honest typo must not eat the
 * allowance for the rest of the 15-minute window.
 */
async function clearCodeAttempts(pool, email) {
  await pool.query(
    `DELETE FROM password_reset_requests WHERE email = $1 AND kind = 'code_attempt'`,
    [email]
  );
}

module.exports = { resetEvents, recordResetEvent, clearCodeAttempts };
