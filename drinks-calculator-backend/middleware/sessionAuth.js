// Session-based authentication helpers (DB-backed).
// A session token is only valid if it exists in user_sessions,
// is active, and has not expired.
const crypto = require('crypto');
const { createSessionCache } = require('../utils/sessionCache');

// Short-lived cache in front of the session query below. Every authenticated
// request otherwise costs a database round-trip; with the cache the common case is
// free. Revocations delete the entry explicitly (see the invalidators at the end),
// so the 30 s window only affects expiry, not a logout or a block.
// SESSION_CACHE_TTL_MS=0 disables it.
const sessionCache = createSessionCache({
  ttlMs: Number(process.env.SESSION_CACHE_TTL_MS ?? 30000),
});

// Cryptographically random session token (not guessable like 'token_<id>_<ts>').
function generateSessionToken() {
  return 'sq_' + crypto.randomBytes(32).toString('hex');
}

// Returns the authenticated user row for a session token, or null.
// Cached for SESSION_CACHE_TTL_MS so a screen making several calls costs one
// lookup, not one per call.
async function getSessionUser(db, token) {
  if (!token) return null;
  const cached = sessionCache.get(token);
  if (cached) return cached;

  const result = await db.query(
    `SELECT u.id, u.username, u.email, u.role, u.company_id, u.is_active
     FROM user_sessions s
     JOIN users u ON s.user_id = u.id
     WHERE s.session_token = $1 AND s.is_active = true AND s.expires_at > NOW()`,
    [token]
  );
  const user = result.rows[0];
  if (!user || !user.is_active) return null;
  sessionCache.set(token, user);
  return user;
}

/** Forget one session (logout, this device only). */
function invalidateSession(token) {
  sessionCache.delete(token);
}

/** Forget every session of a user (blocked, locked, terminated on another device). */
function invalidateUserSessions(userId) {
  sessionCache.deleteForUser(userId);
}

// Express middleware: requires a valid Bearer session token.
function requireSession(db) {
  return async (req, res, next) => {
    try {
      const authHeader = req.headers.authorization;
      const token = authHeader && authHeader.startsWith('Bearer ')
        ? authHeader.split(' ')[1]
        : null;
      const user = await getSessionUser(db, token);
      if (!user) {
        return res.status(401).json({
          status: 'error',
          success: false,
          message: 'Authentication required: invalid or expired session'
        });
      }
      req.user = user;
      req.sessionToken = token;
      next();
    } catch (error) {
      next(error);
    }
  };
}

module.exports = {
  generateSessionToken,
  getSessionUser,
  requireSession,
  invalidateSession,
  invalidateUserSessions,
};
