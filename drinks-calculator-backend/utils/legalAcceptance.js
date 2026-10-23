// utils/legalAcceptance.js
// A Terms of Service / Privacy Policy is only worth having if we can show WHO
// accepted WHICH text WHEN. Until this existed, the signup checkbox lived in the
// Flutter widget and was never sent: nothing proved a user ever agreed, and a
// direct call to /api/auth/register skipped consent entirely.
//
// Design notes:
//  - the SERVER owns the version string (`LEGAL_VERSION`), because the server is
//    what actually served the text that was on screen;
//  - two rows per user (terms + privacy) so each document can be audited alone;
//  - an app build too old to send the flag is tolerated until
//    LEGAL_ACCEPTANCE_REQUIRED=true, but nothing is recorded for it — the gap
//    stays visible instead of being papered over.
const DEFAULT_VERSION = '2026-10';
const DOCUMENTS = ['terms', 'privacy'];

/** The version stamped on an acceptance (e.g. `2026-10`). */
function legalVersion(env = process.env) {
  return (env.LEGAL_VERSION || DEFAULT_VERSION).trim() || DEFAULT_VERSION;
}

/** Whether consent must be present for a registration to succeed. */
function acceptanceRequired(env = process.env) {
  return String(env.LEGAL_ACCEPTANCE_REQUIRED || '').toLowerCase() === 'true';
}

/**
 * Decide whether a registration may proceed.
 *
 * @param {{accepted: boolean|undefined, required: boolean}} args
 * @returns {{ok: boolean, record: boolean, code?: string}}
 */
function checkAcceptance({ accepted, required }) {
  if (accepted === true) return { ok: true, record: true };
  if (accepted === false) return { ok: false, record: false, code: 'legal_not_accepted' };
  return required
    ? { ok: false, record: false, code: 'legal_acceptance_required' }
    : { ok: true, record: false };
}

/**
 * The rows to store for a user who accepted.
 * @returns {Array<{user_id: *, document: string, version: string,
 *                  accepted_at: Date, ip: string|null}>}
 */
function acceptanceRows({
  userId,
  version = DEFAULT_VERSION,
  acceptedAt = new Date(),
  ip = null,
}) {
  return DOCUMENTS.map((document) => ({
    user_id: userId,
    document,
    version,
    accepted_at: acceptedAt,
    ip,
  }));
}

/**
 * Has this user accepted the CURRENT text of every document?
 *
 * Used by `GET /api/auth/legal/status`: an account created by a manager never saw
 * the terms, and a user who accepted an older version has not accepted the new one.
 * Both cases must be asked again.
 *
 * @param {Array<{document: string, version: string}>} rows acceptance rows for the user
 * @param {string} version the version currently published
 */
function hasAcceptedCurrentVersion(rows, version = DEFAULT_VERSION) {
  const wanted = (version || '').toString().trim();
  if (!wanted) return false;
  const accepted = new Set(
    (Array.isArray(rows) ? rows : [])
      .filter((row) => row && String(row.version) === wanted)
      .map((row) => String(row.document))
  );
  return DOCUMENTS.every((document) => accepted.has(document));
}

module.exports = {
  checkAcceptance,
  acceptanceRows,
  hasAcceptedCurrentVersion,
  legalVersion,
  acceptanceRequired,
  DOCUMENTS,
  DEFAULT_VERSION,
};
