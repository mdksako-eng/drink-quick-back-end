// utils/companyOwner.js
// Who owns the company, and does this user own it?
//
// One rule, in one place, because GET /auth/me (what the app calls on every
// start) and the login route must agree: the app gates owner-only actions —
// changing the company logo, branding, clearing company data — on this answer.
// It used to be computed only at login, so after a restart the real owner was
// treated as a plain manager and could no longer change the logo.

/** Pure: does this company row belong to this user? */
function ownsCompanyRow(row, userId) {
  if (!row || row.owner_id == null || userId == null) return false;
  return Number(row.owner_id) === Number(userId);
}

/**
 * Does [user] own their company?
 *
 * Self-heal: companies created before `owner_id` existed have none, which would
 * hide every owner-only action from the shop's real manager. The first Manager
 * to ask claims it — once, and never over an existing owner.
 *
 * Never throws: an owner-lookup failure must not break sign-in.
 *
 * @param {{query: Function}} db
 * @param {{id?: any, _id?: any, company_id?: any, companyId?: any, role?: string}} user
 * @returns {Promise<boolean>}
 */
async function resolveIsOwner(db, user) {
  if (!db || !user) return false;
  const companyId = user.company_id ?? user.companyId;
  const userId = user.id ?? user._id;
  if (companyId == null || userId == null) return false;

  try {
    const own = await db.query(
      'SELECT owner_id FROM companies WHERE id = $1',
      [companyId]
    );
    const row = own.rows.length > 0 ? own.rows[0] : null;
    if (ownsCompanyRow(row, userId)) return true;

    if (row && row.owner_id == null && String(user.role) === 'Manager') {
      const claimed = await db.query(
        'UPDATE companies SET owner_id = $1 WHERE id = $2 AND owner_id IS NULL RETURNING owner_id',
        [userId, companyId]
      );
      return claimed.rows.length > 0 && ownsCompanyRow(claimed.rows[0], userId);
    }
    return false;
  } catch (e) {
    console.log('⚠️ owner lookup skipped:', e.message);
    return false;
  }
}

module.exports = { ownsCompanyRow, resolveIsOwner };
