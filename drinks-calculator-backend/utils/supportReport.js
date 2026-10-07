// backend/utils/supportReport.js
// What a support report is: the categories a user may pick, the rules that make a
// report usable, and the text we email. Pure — no network, no database — so the
// rules stay testable.
//
// Why the context block exists: "it doesn't work" cannot be investigated. Every
// report therefore carries the company, the user, the platform, the app version and
// the screen they were on, captured by the app and never typed by the user.

const CATEGORIES = {
  BUG: 'bug',
  COMPLAINT: 'complaint',
  IDEA: 'idea',
  OTHER: 'other',
};

const CATEGORY_VALUES = Object.values(CATEGORIES);

const MIN_MESSAGE = 10;
const MAX_MESSAGE = 4000;
const MAX_SUBJECT = 120;
const MAX_CONTEXT_FIELD = 120;

/** Context keys we accept from the app; anything else is dropped. */
const CONTEXT_KEYS = ['platform', 'appVersion', 'screen', 'deviceId', 'locale', 'role'];

/**
 * @returns {string} one of CATEGORY_VALUES, defaulting to 'other'
 */
function normalizeCategory(value) {
  const text = String(value || '').trim().toLowerCase();
  return CATEGORY_VALUES.includes(text) ? text : CATEGORIES.OTHER;
}

/** Collapse whitespace so a report pasted from elsewhere still reads cleanly. */
function cleanText(value) {
  return String(value == null ? '' : value).replace(/\s+/g, ' ').trim();
}

/**
 * Keep the message readable but bounded, and never empty.
 * @returns {{ok: boolean, reason: string, value: {category: string, subject: string, message: string}}}
 */
function validateReport({ category, subject, message } = {}) {
  const chosen = normalizeCategory(category);
  const body = String(message == null ? '' : message).trim();
  const cleanSubject = cleanText(subject).slice(0, MAX_SUBJECT);

  if (!body) return { ok: false, reason: 'message_required', value: null };
  if (body.length < MIN_MESSAGE) return { ok: false, reason: 'message_too_short', value: null };
  if (body.length > MAX_MESSAGE) return { ok: false, reason: 'message_too_long', value: null };

  return {
    ok: true,
    reason: 'ok',
    value: {
      category: chosen,
      subject: cleanSubject || defaultSubject(chosen),
      message: body,
    },
  };
}

/** A subject the support inbox can scan, when the user did not type one. */
function defaultSubject(category) {
  switch (normalizeCategory(category)) {
    case CATEGORIES.BUG:
      return 'Bug report';
    case CATEGORIES.COMPLAINT:
      return 'Complaint';
    case CATEGORIES.IDEA:
      return 'Suggestion';
    default:
      return 'Support request';
  }
}

/**
 * Keep only the context we ask for, and bound each value: this text lands in an
 * email and in the database, so it must not be able to carry a novel or a payload.
 */
function sanitizeContext(raw) {
  const out = {};
  if (!raw || typeof raw !== 'object') return out;
  for (const key of CONTEXT_KEYS) {
    const value = cleanText(raw[key]).slice(0, MAX_CONTEXT_FIELD);
    if (value) out[key] = value;
  }
  return out;
}

/** Escape user text before it goes into an HTML email. */
function escapeHtml(value) {
  return String(value == null ? '' : value)
    .replace(/&/g, '&amp;')
    .replace(/</g, '&lt;')
    .replace(/>/g, '&gt;')
    .replace(/"/g, '&quot;')
    .replace(/'/g, '&#39;');
}

/** An opaque, traceable id for a report, so it can be quoted back to the user. */
function newReference(companyId, category, now = Date.now(), random = Math.random) {
  const suffix = Math.floor(random() * 0xffffff).toString(16).padStart(6, '0');
  const who = companyId == null ? 'na' : String(companyId);
  return `sup_${who}_${normalizeCategory(category)}_${now}_${suffix}`;
}

/**
 * The email we send support. Subject line is scannable; the body keeps the user's
 * wording verbatim (escaped) with the context underneath.
 * @returns {{subject: string, html: string, text: string}}
 */
function buildEmail({ report, user, companyName, context, reference } = {}) {
  const value = (report && report.category) ? report : { category: CATEGORIES.OTHER, subject: defaultSubject(), message: '' };
  const who = [user && user.username, companyName].filter(Boolean).join(' @ ') || 'unknown user';
  const subject = `[${value.category}] ${value.subject} — ${who}`;
  const lines = [
    `Reference: ${reference || '(none)'}`,
    `Category:  ${value.category}`,
    `From:      ${who}`,
    `Email:     ${(user && user.email) || '(not set)'}`,
    `Phone:     ${(user && user.phone) || '(not set)'}`,
    '',
    value.message,
  ];
  const contextEntries = Object.entries(sanitizeContext(context));
  if (contextEntries.length) {
    lines.push('', '--- context ---');
    for (const [key, val] of contextEntries) lines.push(`${key}: ${val}`);
  }
  const text = lines.join('\n');
  const html = `<div style="font-family:Arial,sans-serif;max-width:640px">
    <h2 style="margin:0 0 4px">${escapeHtml(value.subject)}</h2>
    <p style="color:#666;margin:0 0 16px">${escapeHtml(value.category)} · ${escapeHtml(who)}</p>
    <pre style="white-space:pre-wrap;background:#f6f7f9;padding:14px;border-radius:8px">${escapeHtml(value.message)}</pre>
    <p style="color:#666;font-size:12px">Reference: ${escapeHtml(reference || '')}<br>Email: ${escapeHtml((user && user.email) || '-')}<br>Phone: ${escapeHtml((user && user.phone) || '-')}</p>
    ${contextEntries.length ? `<p style="color:#888;font-size:12px">${escapeHtml(contextEntries.map(([k, v]) => `${k}=${v}`).join(', '))}</p>` : ''}
  </div>`;
  return { subject, html, text };
}

module.exports = {
  CATEGORIES,
  CATEGORY_VALUES,
  CONTEXT_KEYS,
  MIN_MESSAGE,
  MAX_MESSAGE,
  MAX_SUBJECT,
  normalizeCategory,
  cleanText,
  validateReport,
  defaultSubject,
  sanitizeContext,
  escapeHtml,
  newReference,
  buildEmail,
};
