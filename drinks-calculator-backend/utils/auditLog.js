// utils/auditLog.js
// One row per sensitive action, so "who did that?" has an answer months later.
//
// WHY: block/unblock/delete/role changes, refunds and staff sale corrections all
// move money or access. Until now the only trace was a console line that disappears
// with the log rotation. This writes a durable row.
//
// `record()` is BEST EFFORT on purpose: an audit write must never fail the action it
// documents (a blocked user stays blocked even if the log insert hiccups), but a
// failure is logged loudly.
const MAX_DETAIL = 500;

/** Build the row; pure, so the shape is unit tested. */
function buildEntry({
  companyId = null,
  actorId = null,
  actorName = '',
  action,
  target = '',
  detail = '',
  createdAt = new Date(),
} = {}) {
  return {
    company_id: companyId,
    actor_id: actorId,
    actor_name: (actorName || '').toString().trim().slice(0, 120),
    action: (action || '').toString().trim().slice(0, 80),
    target: (target || '').toString().trim().slice(0, 120),
    detail: (detail || '').toString().trim().slice(0, MAX_DETAIL),
    created_at: createdAt,
  };
}

/** True when the entry is worth storing (an action is mandatory). */
function isValidEntry(entry) {
  return !!(entry && entry.action && entry.action.length > 0);
}

/**
 * Insert the entry, never throwing.
 * @param {{query: Function}} db
 * @returns {Promise<boolean>} whether it was stored
 */
async function record(db, entry) {
  const row = buildEntry(entry);
  if (!isValidEntry(row)) return false;
  try {
    await db.query(
      `INSERT INTO audit_log
         (company_id, actor_id, actor_name, action, target, detail, created_at)
       VALUES ($1,$2,$3,$4,$5,$6,$7)`,
      [row.company_id, row.actor_id, row.actor_name, row.action, row.target, row.detail, row.created_at]
    );
    return true;
  } catch (error) {
    console.error('⚠️ Audit entry not stored:', row.action, '-', error.message);
    return false;
  }
}

module.exports = { buildEntry, isValidEntry, record, MAX_DETAIL };
