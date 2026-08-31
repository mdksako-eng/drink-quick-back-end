// Session-based authentication helpers (DB-backed).
// A session token is only valid if it exists in user_sessions,
// is active, and has not expired.
const crypto = require('crypto');

// Cryptographically random session token (not guessable like 'token_<id>_<ts>').
function generateSessionToken() {
  return 'sq_' + crypto.randomBytes(32).toString('hex');
}

// Returns the authenticated user row for a session token, or null.
async function getSessionUser(db, token) {
  if (!token) return null;
  const result = await db.query(
    `SELECT u.id, u.username, u.email, u.role, u.company_id, u.is_active
     FROM user_sessions s
     JOIN users u ON s.user_id = u.id
     WHERE s.session_token = $1 AND s.is_active = true AND s.expires_at > NOW()`,
    [token]
  );
  const user = result.rows[0];
  if (!user || !user.is_active) return null;
  return user;
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

module.exports = { generateSessionToken, getSessionUser, requireSession };
