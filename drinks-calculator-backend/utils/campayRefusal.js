// utils/campayRefusal.js
// What CamerPay refused, in a form the app can translate.
//
// The provider explains its refusals in its own prose, in its own language, with its
// own links — observed live on 2026-10-14:
//   "Votre période d'essai gratuite s'est terminée le 12/10/2026. Activez un plan
//    pour reprendre. https://camerpay.biz/client/subscription"
// That sentence belongs in a support ticket, not in front of a customer: it names a
// third party, is in one language only, and offers a link the user cannot act on.
// So the route classifies the refusal into a stable code, the app renders its own
// translated sentence, and the provider's words are kept in `providerMessage` for
// the log — and shown as detail only where they are genuinely actionable (which
// document unlocks a KYC limit).
//
// Pure — no Express, no network — so every mapping below is unit tested.

/** Machine-readable outcomes; the app turns these into localized messages. */
const CODES = {
  /** The payment ACCOUNT (the one holding the token) is not active: its own plan or
   *  free trial is over. The customer can do nothing about it. */
  ACCOUNT_INACTIVE: 'campay_account_inactive',
  /** KYC tier or plan volume limit reached on the account collecting the money. */
  QUOTA: 'campay_quota',
  /** The API token itself was rejected. */
  TOKEN: 'campay_token',
  /** The request itself was refused (a number the operator rejects, a closed rail). */
  REQUEST_REJECTED: 'campay_request_rejected',
  /** Nothing configured for this rail at all. */
  NOT_CONFIGURED: 'campay_not_configured',
  UNKNOWN: 'campay_error',
};

/**
 * Phrases CamerPay uses when the ACCOUNT is the problem rather than the request:
 * its own plan or free trial. Matched against the message AND the upgrade link, so
 * a payload that only carries the portal URL is still recognised.
 */
const ACCOUNT_PATTERNS = [
  /p[ée]riode\s+d['’]?\s*essai/i,
  /essai\s+gratuit/i,
  /free\s+trial/i,
  /(trial|essai)[^.]{0,40}(expir|termin|ended|over|finish)/i,
  /activez\s+un\s+plan/i,
  /activate\s+a\s+plan/i,
  /client\/subscription/i,
];

function text(value) {
  return value == null ? '' : String(value);
}

/** Is CamerPay refusing because the account itself is not active? */
function looksLikeAccountRefusal(message, upgradeUrl) {
  const haystack = `${text(message)} ${text(upgradeUrl)}`;
  return ACCOUNT_PATTERNS.some((pattern) => pattern.test(haystack));
}

/**
 * Classify one refusal.
 *
 * `accountLevel` is true when the problem is the payment account itself, which the
 * customer cannot fix — the app then says "try again later / contact support"
 * instead of inviting them to correct something on their side.
 */
function classify({ status, code, message, upgradeUrl } = {}) {
  if (looksLikeAccountRefusal(message, upgradeUrl)) {
    return { code: CODES.ACCOUNT_INACTIVE, accountLevel: true };
  }
  const httpStatus = Number(status);
  if (httpStatus === 402) return { code: CODES.QUOTA, accountLevel: false };
  if (httpStatus === 401 || httpStatus === 403) {
    return { code: CODES.TOKEN, accountLevel: false };
  }
  if (httpStatus === 422 || httpStatus === 400) {
    return { code: CODES.REQUEST_REJECTED, accountLevel: false };
  }
  return { code: CODES.UNKNOWN, accountLevel: false };
}

/**
 * The neutral English sentence for a code. The app prefers its own translation
 * (i18n key `payErr…`); this is the fallback for anything that is not the app —
 * logs, support tooling, a curl call.
 */
function userMessageFor(code) {
  switch (code) {
    case CODES.ACCOUNT_INACTIVE:
      return 'Payments cannot be taken at the moment. Please try again later, or ask support to check the payment account.';
    case CODES.QUOTA:
      return 'This payment was refused because the payment account has reached its limit.';
    case CODES.TOKEN:
      return 'Payments are not connected correctly. Please contact support.';
    case CODES.REQUEST_REJECTED:
      return 'The payment details were refused. Check the number and try again.';
    case CODES.NOT_CONFIGURED:
      return 'Payments are not available yet.';
    default:
      return 'The payment could not be started. Please try again.';
  }
}

/**
 * Is the provider's own wording worth showing UNDER the translated sentence?
 * Only for a KYC/volume limit, where it names the document that unlocks the next
 * tier — the one case the route deliberately used to hand back verbatim.
 */
function providerDetailIsUseful(code) {
  return code === CODES.QUOTA || code === CODES.REQUEST_REJECTED;
}

module.exports = {
  CODES,
  ACCOUNT_PATTERNS,
  looksLikeAccountRefusal,
  classify,
  userMessageFor,
  providerDetailIsUseful,
};
