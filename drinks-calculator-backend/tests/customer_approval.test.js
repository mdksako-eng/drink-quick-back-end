/**
 * Customer account ("customer number") rules — no database required.
 *
 * Covers the rule the shop asked for:
 *   - STAFF enrol a customer; the account waits as 'pending'
 *   - the MANAGER holds the final say: approve / reject / block / re-limit
 *   - a manager's own enrolment is approved on the spot
 *   - credit may only be given on an approved account
 *   - customer numbers are handed out once and never reused
 *
 * Run with: npm test
 */
const {
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
} = require('../utils/customerApproval');

// Company 7: one co-manager, one staff member, one customer, one admin.
const owner = { id: 3, role: 'Manager', company_id: 7 };
const coManager = { id: 9, role: 'Manager', company_id: 7 };
const staff = { id: 11, role: 'Staff', company_id: 7 };
const customer = { id: 42, role: 'Customer', company_id: null };
const admin = { id: 1, role: 'Administrator', company_id: null };

describe('who may enrol a customer', () => {
  test('staff may enrol', () => {
    expect(canEnrollCustomer(staff).ok).toBe(true);
  });

  test('managers may enrol', () => {
    expect(canEnrollCustomer(owner).ok).toBe(true);
    expect(canEnrollCustomer(coManager).ok).toBe(true);
    expect(canEnrollCustomer(admin).ok).toBe(true);
  });

  test('a customer account may not enrol another customer', () => {
    expect(canEnrollCustomer(customer).ok).toBe(false);
  });

  test('an anonymous request may not enrol', () => {
    expect(canEnrollCustomer(null).ok).toBe(false);
  });
});

describe('enrolment status', () => {
  test('a staff enrolment waits for the manager', () => {
    expect(initialStatusForRole('Staff')).toBe('pending');
    expect(initialStatusForRole('staff')).toBe('pending');
  });

  test('a manager enrolment is final immediately', () => {
    expect(initialStatusForRole('Manager')).toBe('approved');
    expect(initialStatusForRole('Admin')).toBe('approved');
    expect(initialStatusForRole('Administrator')).toBe('approved');
  });
});

describe('the manager holds the final say', () => {
  test('staff may not decide', () => {
    expect(canDecideCustomer(staff).ok).toBe(false);
    expect(canDecideCustomer(staff).reason).toMatch(/manager/i);
  });

  test('managers and administrators may decide', () => {
    expect(canDecideCustomer(owner).ok).toBe(true);
    expect(canDecideCustomer(coManager).ok).toBe(true);
    expect(canDecideCustomer(admin).ok).toBe(true);
  });
});

describe('status transitions', () => {
  test('pending may be approved or rejected', () => {
    expect(canDecideStatus('pending', 'approved').ok).toBe(true);
    expect(canDecideStatus('pending', 'rejected').ok).toBe(true);
  });

  test('an approved account may only be blocked', () => {
    expect(canDecideStatus('approved', 'blocked').ok).toBe(true);
    expect(canDecideStatus('approved', 'pending').ok).toBe(false);
  });

  test('a blocked or rejected account can be restored by a manager', () => {
    expect(canDecideStatus('blocked', 'approved').ok).toBe(true);
    expect(canDecideStatus('rejected', 'approved').ok).toBe(true);
  });

  test('re-setting the same status is refused', () => {
    expect(canDecideStatus('approved', 'approved').ok).toBe(false);
  });

  test('an unknown status is refused', () => {
    expect(canDecideStatus('pending', 'deleted').ok).toBe(false);
  });
});

describe('credit is only for an approved account', () => {
  test('only approved customers can hold credit', () => {
    expect(canHoldCredit({ status: 'approved' })).toBe(true);
    expect(canHoldCredit({ status: 'pending' })).toBe(false);
    expect(canHoldCredit({ status: 'blocked' })).toBe(false);
    expect(canHoldCredit({ status: 'rejected' })).toBe(false);
    expect(canHoldCredit(null)).toBe(false);
  });

  test('a pending customer cannot be charged', () => {
    const result = canAddLedgerEntry({
      user: staff, customer: { status: 'pending' }, kind: 'charge', amount: 500,
    });
    expect(result.ok).toBe(false);
    expect(result.reason).toMatch(/approved/i);
  });

  test('an approved customer can be charged and can pay', () => {
    const approved = { status: 'approved' };
    expect(
      canAddLedgerEntry({ user: staff, customer: approved, kind: 'charge', amount: 500 }).ok
    ).toBe(true);
    expect(
      canAddLedgerEntry({ user: staff, customer: approved, kind: 'payment', amount: 500 }).ok
    ).toBe(true);
  });

  test('zero, negative and non-numeric amounts are refused', () => {
    const approved = { status: 'approved' };
    for (const amount of [0, -100, 'abc', null]) {
      expect(
        canAddLedgerEntry({ user: staff, customer: approved, kind: 'charge', amount }).ok
      ).toBe(false);
    }
  });

  test('an unknown entry kind is refused', () => {
    expect(
      canAddLedgerEntry({
        user: staff, customer: { status: 'approved' }, kind: 'refund', amount: 100,
      }).ok
    ).toBe(false);
  });
});

describe('customer numbers', () => {
  test('starts at C-0001 for an empty company', () => {
    expect(nextCustomerNumber([])).toBe('C-0001');
  });

  test('skips numbers that are already taken', () => {
    expect(nextCustomerNumber(['C-0001', 'C-0002'])).toBe('C-0003');
    expect(nextCustomerNumber(['C-0001', 'C-0003'])).toBe('C-0002');
  });

  test('tolerates a company with numbers from another format', () => {
    expect(nextCustomerNumber(['OLD-1', null, ''])).toBe('C-0001');
  });
});

describe('phone normalisation', () => {
  test('spaces, dashes and the country code do not matter', () => {
    expect(normalizePhone('6 77 12 34 56')).toBe('677123456');
    expect(normalizePhone('+237 677-123-456')).toBe('237677123456');
    expect(normalizePhone(null)).toBe('');
  });
});

describe('credit limit', () => {
  test('no limit set means no warning', () => {
    expect(exceedsCreditLimit({ balance: 99999, amount: 1, creditLimit: 0 })).toBe(false);
  });

  test('warns when the new balance passes the limit', () => {
    expect(exceedsCreditLimit({ balance: 900, amount: 200, creditLimit: 1000 })).toBe(true);
    expect(exceedsCreditLimit({ balance: 900, amount: 100, creditLimit: 1000 })).toBe(false);
  });
});

describe('ledger totals', () => {
  test('balance is what was charged minus what was paid', () => {
    const totals = sumLedger([
      { kind: 'charge', amount: 5000 },
      { kind: 'payment', amount: 2000 },
      { kind: 'charge', amount: 1000 },
    ]);
    expect(totals.charged).toBe(6000);
    expect(totals.paid).toBe(2000);
    expect(totals.balance).toBe(4000);
  });

  test('an empty ledger owes nothing', () => {
    expect(sumLedger([]).balance).toBe(0);
    expect(sumLedger(null).balance).toBe(0);
  });
});
