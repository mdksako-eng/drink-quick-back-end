// utils/containerLedger.js
// Pure rules for returnable containers (crates and bottles) a customer holds.
// No Express, no DB writes — so every rule below is unit tested.
//
// WHY THIS EXISTS
//   Beer moves in returnable crates and bottles. The crate the shop hands over
//   belongs to the shop (or to the distributor it came from), so "who is holding
//   my empties?" is real money standing in a customer's yard. The credit ledger
//   answers "who owes me money"; this answers "who owes me containers".
//
// THE SHAPE MIRRORS THE CREDIT LEDGER ON PURPOSE
//   A balance is NEVER stored — it is summed from the movements, exactly like
//   `charged - paid` in utils/customerApproval.js. Two staff recording at the
//   same moment therefore cannot lose an entry, and a corrected ledger is always
//   consistent with its own history.
//
//   outstanding = sum(out) - sum(back) - sum(writeoff)
//
// WHO DECIDES WHAT:
//   * STAFF may hand a container out and take one back — that is a physical fact
//     at the counter, like a restock.
//   * A MANAGER alone may WRITE OFF a container (lost, broken, never came back):
//     it is stock quietly disappearing, the same rule as voids and credit-limit
//     overrides.
//   * Nobody may take back or write off more than is actually outstanding.

const { isManagerRole } = require('./customerApproval');

const CONTAINER_KINDS = ['out', 'back', 'writeoff'];

function normalizeRole(role) {
  return (role || '').toString().trim().toLowerCase();
}

/** Recording a movement at the counter: any role except the customer's own. */
function canRecordContainers(user) {
  if (!user) return { ok: false, reason: 'Authentication required' };
  if (normalizeRole(user.role) === 'customer') {
    return { ok: false, reason: 'Customers cannot record containers' };
  }
  return { ok: true };
}

/** A write-off is stock disappearing, so a manager alone may do it. */
function canWriteOff(user) {
  if (!user) return { ok: false, reason: 'Authentication required' };
  if (isManagerRole(user.role)) return { ok: true };
  return { ok: false, reason: 'Only a manager can write off a container' };
}

/** The container catalogue (names, deposits) is shop setup, so a manager owns it. */
function canManageTypes(user) {
  if (!user) return { ok: false, reason: 'Authentication required' };
  if (isManagerRole(user.role)) return { ok: true };
  return { ok: false, reason: 'Only a manager can change the container list' };
}

/** Which movements this user may record at all. */
function canDecideKind(user, kind) {
  if (!CONTAINER_KINDS.includes(kind)) {
    return { ok: false, reason: 'Unknown container movement' };
  }
  if (kind === 'writeoff') return canWriteOff(user);
  return canRecordContainers(user);
}

/**
 * A quantity is a whole number of containers, greater than zero.
 * Returns { ok, value, reason } so the route can answer with the exact message.
 */
function validateQuantity(quantity) {
  const value = Number(quantity);
  if (!Number.isFinite(value)) {
    return { ok: false, reason: 'Quantity must be a number' };
  }
  if (!Number.isInteger(value)) {
    return { ok: false, reason: 'Quantity must be a whole number of containers' };
  }
  if (value <= 0) {
    return { ok: false, reason: 'Quantity must be greater than zero' };
  }
  return { ok: true, value };
}

/** Totals for one customer's container ledger. */
function sumContainers(entries) {
  let out = 0;
  let back = 0;
  let writtenOff = 0;
  for (const entry of entries || []) {
    const quantity = Number(entry && entry.quantity) || 0;
    if (entry && entry.kind === 'back') back += quantity;
    else if (entry && entry.kind === 'writeoff') writtenOff += quantity;
    else if (entry && entry.kind === 'out') out += quantity;
  }
  return { out, back, writtenOff, outstanding: out - back - writtenOff };
}

/** What is still out for ONE container type (0 when they hold none). */
function outstandingFor(entries, containerTypeId) {
  const mine = (entries || []).filter(
    (e) => Number(e && e.containerTypeId) === Number(containerTypeId)
  );
  return sumContainers(mine).outstanding;
}

/**
 * The whole ledger grouped by container type, biggest pile first — the list a
 * manager actually reads. Types with nothing outstanding are dropped, and
 * `value` is only informational (deposit x outstanding): containers are goods,
 * not cash, so this never enters the shift or Z-report maths.
 */
function outstandingByType(types, entries) {
  return (types || [])
    .map((type) => {
      const outstanding = outstandingFor(entries, type.id);
      const depositValue = Number(type.depositValue) || 0;
      return {
        containerTypeId: type.id,
        name: type.name,
        depositValue,
        outstanding,
        value: Math.round(outstanding * depositValue * 100) / 100,
      };
    })
    .filter((row) => row.outstanding !== 0)
    .sort(
      (a, b) => b.outstanding - a.outstanding || a.name.localeCompare(b.name)
    );
}

/**
 * Whether a movement may be written.
 * `outstanding` is what the customer holds RIGHT NOW for that container type.
 * Returns { ok, reason } so the route answers with the exact message.
 */
function validateMovement({ user, kind, quantity, outstanding }) {
  const kindCheck = canDecideKind(user, kind);
  if (!kindCheck.ok) return kindCheck;

  const quantityCheck = validateQuantity(quantity);
  if (!quantityCheck.ok) return quantityCheck;

  // Only 'out' adds to the pile; the other two take from it, and the pile can
  // never go below zero — the same rule the returns ceiling uses.
  if (kind !== 'out') {
    const held = Number(outstanding) || 0;
    if (quantityCheck.value > held) {
      return {
        ok: false,
        reason:
          kind === 'writeoff'
            ? `Only ${held} container(s) are outstanding, so ${quantityCheck.value} cannot be written off`
            : `Only ${held} container(s) are outstanding, so ${quantityCheck.value} cannot come back`,
      };
    }
  }

  return { ok: true, value: quantityCheck.value };
}

/**
 * One row per customer for the company-wide "who holds my containers" list,
 * biggest holder first. Rows are { customerId, customerNumber, name, outstanding }.
 */
function orderByOutstanding(rows) {
  return [...(rows || [])]
    .filter((row) => (Number(row && row.outstanding) || 0) !== 0)
    .sort(
      (a, b) =>
        (Number(b.outstanding) || 0) - (Number(a.outstanding) || 0) ||
        String(a.customerNumber || '').localeCompare(
          String(b.customerNumber || '')
        )
    );
}

module.exports = {
  CONTAINER_KINDS,
  isManagerRole,
  canRecordContainers,
  canWriteOff,
  canManageTypes,
  canDecideKind,
  validateQuantity,
  sumContainers,
  outstandingFor,
  outstandingByType,
  validateMovement,
  orderByOutstanding,
};
