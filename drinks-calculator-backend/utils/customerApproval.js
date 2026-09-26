// utils/customerApproval.js
// Pure rules for customer accounts ("customer numbers") and their credit ledger.
// No Express, no DB writes — so every rule below is unit tested.
//
// WHO DECIDES WHAT:
//   * STAFF enrol a customer (name + phone). The account starts as 'pending'
//     and may not hold any credit yet.
//   * A MANAGER holds the final say: only a Manager (or a platform
//     Administrator) may approve, reject, block or re-limit an account.
//   * A Manager who enrols a customer gets it approved immediately — they are
//     the approver, so there is nothing left to wait for.
//
// A pending / rejected / blocked account can never be charged on a tab: credit
// is the shop's money, so the ledger only accepts an approved account.

const MANAGER_ROLES = ['Manager', 'Administrator', 'Admin'];
const CUSTOMER_STATUSES = ['pending', 'approved', 'rejected', 'blocked'];
const LEDGER_KINDS = ['charge', 'payment'];

// Credit limit handed to a newly approved customer (0 = no limit set, so a
// charge always needs an explicit override until the manager sets one).
const DEFAULT_CREDIT_LIMIT = 0;

function normalizeRole(role) {
  return (role || '').toString().trim().toLowerCase();
}

function isManagerRole(role) {
  const r = normalizeRole(role);
  return MANAGER_ROLES.some((m) => m.toLowerCase() === r);
}

/**
 * Whether this user may open a customer account at all.
 * Staff may enrol; a plain Customer may not.
 */
function canEnrollCustomer(user) {
  if (!user) return { ok: false, reason: 'Authentication required' };
  const role = normalizeRole(user.role);
  if (role === 'customer') {
    return { ok: false, reason: 'Customers cannot open a customer account' };
  }
  if (isManagerRole(user.role) || role === 'staff') return { ok: true };
  return { ok: false, reason: 'Your role cannot enrol customers' };
}

/**
 * The status an enrolment starts in.
 * Managers approve their own enrolments; staff enrolments wait for a manager.
 */
function initialStatusForRole(role) {
  return isManagerRole(role) ? 'approved' : 'pending';
}

/**
 * Whether this user may decide (approve / reject / block / re-limit).
 * This is the "manager holds the final say" rule.
 */
function canDecideCustomer(user) {
  if (!user) return { ok: false, reason: 'Authentication required' };
  if (isManagerRole(user.role)) return { ok: true };
  return {
    ok: false,
    reason: 'Only a manager can approve, reject or block a customer',
  };
}

/**
 * Allowed status moves. The happy path is pending -> approved (or rejected) and
 * approved -> blocked; a manager may also change their mind and restore an
 * account ('rejected' / 'blocked' -> 'approved').
 */
const STATUS_TRANSITIONS = {
  pending: ['approved', 'rejected'],
  approved: ['blocked'],
  rejected: ['approved'],
  blocked: ['approved'],
};

function canDecideStatus(current, next) {
  if (!CUSTOMER_STATUSES.includes(next)) {
    return { ok: false, reason: 'Unknown customer status' };
  }
  const from = CUSTOMER_STATUSES.includes(current) ? current : 'pending';
  if (from === next) return { ok: false, reason: `Customer is already ${next}` };
  const allowed = STATUS_TRANSITIONS[from] || [];
  if (!allowed.includes(next)) {
    return { ok: false, reason: `Cannot move a ${from} customer to ${next}` };
  }
  return { ok: true };
}

/** Only an approved account may hold a tab. */
function canHoldCredit(customer) {
  return !!customer && customer.status === 'approved';
}

/**
 * The next free customer number for a company: 000001, 000002, … — six digits,
 * which is the shop's format. Taken numbers are skipped, and a number is
 * compared by its DIGITS, so an older 4-digit row ("C-0001") still blocks the
 * six-digit "000001" instead of handing the same number out twice.
 *
 * Pass `{ prefix: 'C', width: 4 }` to get the older "C-0001" style back.
 */
function nextCustomerNumber(existingNumbers, { prefix = '', width = 6 } = {}) {
  const taken = new Set();
  const takenDigits = new Set();
  for (const value of existingNumbers || []) {
    if (value == null) continue;
    const text = String(value).trim();
    if (text === '') continue;
    taken.add(text);
    const tail = numericTail(text);
    if (tail !== null) takenDigits.add(tail);
  }

  let counter = 1;
  // Guard against an endless loop on a corrupt table.
  while (counter <= 10000000) {
    const digits = String(counter).padStart(width, '0');
    // A prefix is joined with a dash ("C-0001"); without one the number is
    // just the digits ("000001").
    const candidate = prefix ? `${prefix}-${digits}` : digits;
    const tail = numericTail(digits);
    if (!taken.has(candidate) && (tail === null || !takenDigits.has(tail))) {
      return candidate;
    }
    counter += 1;
  }
  const fallback = String(Date.now());
  return prefix ? `${prefix}-${fallback}` : fallback;
}

/** The number without its prefix and leading zeros ("C-0001" -> "1"). */
function numericTail(value) {
  const digits = (value == null ? '' : String(value)).replace(/\D/g, '');
  if (digits === '') return null;
  if (digits.length > 15) return digits; // too long to compare as a number
  return String(parseInt(digits, 10));
}

/** Digits only, so "6 77 12 34 56" and "+237 677123456" match the same person. */
function normalizePhone(phone) {
  return (phone == null ? '' : String(phone)).replace(/\D/g, '');
}

/**
 * Whether a ledger entry may be written.
 * Returns { ok, reason } so the route can answer with the exact message.
 */
function canAddLedgerEntry({ user, customer, kind, amount }) {
  if (!user) return { ok: false, reason: 'Authentication required' };
  if (!customer) return { ok: false, reason: 'Unknown customer' };
  if (!LEDGER_KINDS.includes(kind)) {
    return { ok: false, reason: 'Unknown ledger entry type' };
  }
  if (!canHoldCredit(customer)) {
    return {
      ok: false,
      reason: 'This customer has no approved account, so no credit can be given',
    };
  }
  const value = Number(amount);
  if (!Number.isFinite(value) || value <= 0) {
    return { ok: false, reason: 'Amount must be greater than zero' };
  }
  return { ok: true };
}

/**
 * Whether a new charge would push the balance past the credit limit.
 * The limit is a warning, not a wall: a manager may still override it, and the
 * route asks for that override explicitly.
 */
function exceedsCreditLimit({ balance, amount, creditLimit }) {
  const limit = Number(creditLimit) || 0;
  if (limit <= 0) return false; // no limit set -> nothing to exceed
  const next = (Number(balance) || 0) + (Number(amount) || 0);
  return next > limit;
}

/** Totals for one customer's ledger: charged, paid, and what is still owed. */
function sumLedger(entries) {
  let charged = 0;
  let paid = 0;
  for (const entry of entries || []) {
    const amount = Number(entry && entry.amount) || 0;
    if (entry && entry.kind === 'payment') {
      paid += amount;
    } else if (entry && entry.kind === 'charge') {
      charged += amount;
    }
  }
  return { charged, paid, balance: charged - paid };
}

module.exports = {
  MANAGER_ROLES,
  CUSTOMER_STATUSES,
  LEDGER_KINDS,
  DEFAULT_CREDIT_LIMIT,
  STATUS_TRANSITIONS,
  isManagerRole,
  canEnrollCustomer,
  initialStatusForRole,
  canDecideCustomer,
  canDecideStatus,
  canHoldCredit,
  nextCustomerNumber,
  normalizePhone,
  canAddLedgerEntry,
  exceedsCreditLimit,
  sumLedger,
};
