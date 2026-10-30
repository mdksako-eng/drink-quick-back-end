// backend/utils/credentialChange.js
// What a CamerPay credential change actually did, and who has to hear about it.
// Pure - no database, no network - so the rule is unit tested.
//
// WHY IT EXISTS: replacing a company's CamerPay API token is the one settings
// action that can silently redirect that company's money to a different account.
// Two things follow from that, and both live here so they cannot drift apart:
//   - the change is described for the audit trail (never with the values: the audit
//     log is read by people and must not become a place a token can leak from);
//   - the company owner is told, because the owner may not be the person who did it.

/** The audit action name for every CamerPay credential change. */
const ACTIONS = { CREDENTIAL_CHANGED: 'company.payment_credential' };

/**
 * A human sentence for the audit row.
 * @param {{tokenReplaced?: boolean, secretReplaced?: boolean, webhookRotated?: boolean, enabled?: boolean}} change
 * @returns {string} e.g. 'api token replaced; collection enabled'
 */
function describeChange({
  tokenReplaced = false,
  secretReplaced = false,
  webhookRotated = false,
  enabled,
} = {}) {
  const parts = [];
  if (tokenReplaced) parts.push('api token replaced');
  if (secretReplaced) parts.push('webhook secret replaced');
  if (webhookRotated) parts.push('webhook token rotated');
  if (enabled !== undefined) parts.push(`collection ${enabled ? 'enabled' : 'disabled'}`);
  return parts.join('; ') || 'no change';
}

/**
 * Does this change decide where the company's money goes?
 *
 * Only the token does. Rotating the webhook token or flipping the enable switch
 * moves no money, so those stay a one-click action - asking for a password on every
 * toggle would train people to type it without thinking.
 */
function redirectsMoney({ tokenReplaced = false } = {}) {
  return Boolean(tokenReplaced);
}

/**
 * Should the owner be emailed? The owner is the party whose money is at stake, so
 * any change that can move it - or that could break collection - is worth telling
 * them about.
 */
function needsOwnerNotice({ tokenReplaced = false, secretReplaced = false } = {}) {
  return Boolean(tokenReplaced || secretReplaced);
}

module.exports = { ACTIONS, describeChange, redirectsMoney, needsOwnerNotice };
