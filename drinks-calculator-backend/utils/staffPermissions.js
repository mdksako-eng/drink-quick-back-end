// utils/staffPermissions.js
// Pure authorization helpers for staff management (no Express, no DB writes).
//
// A company has exactly one owner (companies.owner_id) and the owner account
// sits at the top of the hierarchy: a co-manager may never edit or block it.
// The owner may edit their own profile and a platform Administrator may always
// override — the same rule the block / unblock endpoints already enforce.

/**
 * Reads the company's owner id. Tolerates an old database that has no
 * owner_id column yet: returns null instead of throwing.
 */
async function getCompanyOwnerId(db, companyId) {
  if (companyId == null) return null;
  try {
    const result = await db.query('SELECT owner_id FROM companies WHERE id = $1', [companyId]);
    return result.rows.length > 0 ? result.rows[0].owner_id : null;
  } catch (e) {
    return null;
  }
}

/**
 * True when `user` is the owner of `companyId`.
 * The company is compared as well so an id collision across two companies can
 * never be mistaken for ownership.
 */
function isCompanyOwner(user, ownerId, companyId) {
  if (user == null || user.id == null) return false;
  if (user.company_id != null && companyId != null && user.company_id !== companyId) {
    return false;
  }
  return Number(ownerId) === Number(user.id);
}

/**
 * Whether `requester` may edit `target`.
 *
 * Returns `{ ok, reason?, targetIsOwner? }` so the API can return the exact
 * message and the caller can apply the owner-specific role rule.
 *
 * Rules, in order:
 *   1. An Administrator account is never editable (even by another admin).
 *   2. A platform Administrator may edit anyone else.
 *   3. A manager may only edit users inside their own company.
 *   4. The company OWNER may only be edited by themselves or an Administrator,
 *      so a co-manager can never rename, re-email or demote the founder.
 */
function canEditStaff({ requester, target, ownerId, isAdmin = false }) {
  if (target && target.role === 'Administrator') {
    return { ok: false, reason: 'Cannot edit an Administrator' };
  }
  if (isAdmin) return { ok: true, targetIsOwner: false };

  if (target && target.company_id != null &&
      requester && requester.company_id != null &&
      target.company_id !== requester.company_id) {
    return { ok: false, reason: 'You can only manage users in your own company' };
  }

  const companyId = target ? target.company_id : null;
  const targetIsOwner = isCompanyOwner(target, ownerId, companyId);
  if (targetIsOwner && !isCompanyOwner(requester, ownerId, companyId)) {
    return {
      ok: false,
      reason: 'Only the company owner can edit the owner account',
    };
  }

  return { ok: true, targetIsOwner };
}

module.exports = { getCompanyOwnerId, isCompanyOwner, canEditStaff };
