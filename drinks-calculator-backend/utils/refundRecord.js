// utils/refundRecord.js
// Refunds are RECORDED here; the money itself moves in the provider's dashboard
// (CamPay/Notch Pay), because no refund API is wired into this backend.
//
// That makes the record the only proof the company has: who refunded what, why,
// and against which provider reference. So the rules are strict:
//   • a reason is required (an unexplained refund is unauditable);
//   • the amount must be positive and never exceed what is still refundable on the
//     order (a refund cannot give back more than was collected);
//   • a provider reference is expected, because that is what ties our row to the
//     line on the provider statement.
// Pure — no Express, no DB — so every rule is unit tested.
function toAmount(value) {
  const number = Number(value);
  return Number.isFinite(number) ? Math.round(number * 100) / 100 : NaN;
}

/**
 * @param {{amount: *, reason: *, reference?: *, orderTotal?: number,
 *          alreadyRefunded?: number}} args
 * @returns {{ok: boolean, reason?: string, amount?: number, note?: string}}
 */
function validateRefund({
  amount,
  reason,
  reference,
  orderTotal = null,
  alreadyRefunded = 0,
} = {}) {
  const value = toAmount(amount);
  if (!Number.isFinite(value) || value <= 0) {
    return { ok: false, reason: 'A refund needs a positive amount' };
  }

  const text = (reason || '').toString().trim();
  if (!text) return { ok: false, reason: 'A reason is required to record a refund' };
  if (text.length > 200) {
    return { ok: false, reason: 'The reason is too long (200 characters max)' };
  }

  if (orderTotal != null) {
    const total = toAmount(orderTotal);
    const already = toAmount(alreadyRefunded) || 0;
    if (Number.isFinite(total)) {
      const remaining = Math.round((total - already) * 100) / 100;
      if (value > remaining + 0.001) {
        return {
          ok: false,
          reason: `This order has ${remaining} left to refund`,
        };
      }
    }
  }

  const ref = (reference || '').toString().trim();
  return {
    ok: true,
    amount: value,
    // Not fatal: an operator may not have the reference to hand, but the record
    // says so plainly so a manager can chase it.
    note: ref ? null : 'no provider reference recorded',
  };
}

/** The row to store for an approved refund. */
function buildRefundRow({
  companyId,
  orderId,
  amount,
  reason,
  reference = '',
  method = 'card',
  performedBy,
  performedByName,
  status = 'approved',
  createdAt = new Date(),
}) {
  return {
    company_id: companyId,
    order_id: orderId ?? null,
    amount,
    reason: (reason || '').toString().trim(),
    reference: (reference || '').toString().trim(),
    method: (method || '').toString().trim() || 'card',
    performed_by: performedBy ?? null,
    performed_by_name: (performedByName || '').toString().trim(),
    status,
    created_at: createdAt,
  };
}

module.exports = { validateRefund, buildRefundRow };
