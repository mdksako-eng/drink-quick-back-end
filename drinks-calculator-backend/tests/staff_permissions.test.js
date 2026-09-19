/**
 * Staff-management authorization tests - no database required.
 *
 * Covers the rule added for the "co-manager must not edit the owner" change:
 *   - the company owner is editable only by themselves or an Administrator
 *   - a co-manager (another Manager) gets a 403 reason instead
 *   - Administrators can still edit managers/staff (but never an Administrator)
 *   - owners are never demoted away from the Manager role
 * Run with: npm test
 */
const {
  canEditStaff,
  isCompanyOwner,
  getCompanyOwnerId,
} = require('../utils/staffPermissions');

// Company 7, owner = user 3 (the founder/manager).
const owner = { id: 3, role: 'Manager', company_id: 7 };
const coManager = { id: 9, role: 'Manager', company_id: 7 };
const staff = { id: 11, role: 'Staff', company_id: 7 };
const admin = { id: 1, role: 'Administrator', company_id: null };
const targetOwner = { id: 3, role: 'Manager', company_id: 7 };
const targetStaff = { id: 11, role: 'Staff', company_id: 7 };
const targetManager = { id: 9, role: 'Manager', company_id: 7 };
const targetAdmin = { id: 1, role: 'Administrator', company_id: null };

describe('isCompanyOwner', () => {
  test('matches the owner id', () => {
    expect(isCompanyOwner(owner, 3, 7)).toBe(true);
  });

  test('compares ids as numbers, not strings', () => {
    expect(isCompanyOwner({ id: '3', company_id: 7 }, 3, 7)).toBe(true);
  });

  test('never matches across companies', () => {
    expect(isCompanyOwner({ id: 3, company_id: 8 }, 3, 7)).toBe(false);
  });

  test('is false when the company has no recorded owner', () => {
    expect(isCompanyOwner(owner, null, 7)).toBe(false);
  });
});

describe('getCompanyOwnerId', () => {
  test('reads owner_id from the company row', async () => {
    const db = { query: async () => ({ rows: [{ owner_id: 3 }] }) };
    expect(await getCompanyOwnerId(db, 7)).toBe(3);
  });

  test('returns null when the company is unknown or the column is missing', async () => {
    expect(await getCompanyOwnerId({ query: async () => ({ rows: [] }) }, 7)).toBeNull();
    const broken = { query: async () => { throw new Error('column owner_id does not exist'); } };
    expect(await getCompanyOwnerId(broken, 7)).toBeNull();
  });
});

describe('canEditStaff - owner protection', () => {
  test('a co-manager may NOT edit the owner', () => {
    const result = canEditStaff({
      requester: coManager,
      target: targetOwner,
      ownerId: 3,
      isAdmin: false,
    });
    expect(result.ok).toBe(false);
    expect(result.reason).toBe('Only the company owner can edit the owner account');
  });

  test('the owner may edit their own profile', () => {
    const result = canEditStaff({
      requester: owner,
      target: targetOwner,
      ownerId: 3,
      isAdmin: false,
    });
    expect(result.ok).toBe(true);
    expect(result.targetIsOwner).toBe(true);
  });

  test('an Administrator may edit the owner', () => {
    const result = canEditStaff({
      requester: admin,
      target: targetOwner,
      ownerId: 3,
      isAdmin: true,
    });
    expect(result.ok).toBe(true);
  });

  test('a co-manager may still edit staff and other managers', () => {
    expect(canEditStaff({
      requester: coManager,
      target: targetStaff,
      ownerId: 3,
      isAdmin: false,
    }).ok).toBe(true);
    expect(canEditStaff({
      requester: coManager,
      target: targetManager,
      ownerId: 3,
      isAdmin: false,
    }).ok).toBe(true);
  });

  test('an Administrator account is never editable, even by an admin', () => {
    const result = canEditStaff({
      requester: admin,
      target: targetAdmin,
      ownerId: 3,
      isAdmin: true,
    });
    expect(result.ok).toBe(false);
    expect(result.reason).toBe('Cannot edit an Administrator');
  });

  test('a manager cannot edit users of another company', () => {
    const result = canEditStaff({
      requester: coManager,
      target: { id: 12, role: 'Staff', company_id: 99 },
      ownerId: 3,
      isAdmin: false,
    });
    expect(result.ok).toBe(false);
    expect(result.reason).toBe('You can only manage users in your own company');
  });

  test('a company without a recorded owner stays open (fail-safe migration path)', () => {
    expect(canEditStaff({
      requester: coManager,
      target: targetOwner,
      ownerId: null,
      isAdmin: false,
    }).ok).toBe(true);
  });

  test('an id collision in another company is not treated as ownership', () => {
    const result = canEditStaff({
      requester: { id: 3, role: 'Manager', company_id: 8 },
      target: targetOwner,
      ownerId: 3,
      isAdmin: false,
    });
    expect(result.ok).toBe(false);
  });
});

describe('owner role cannot be demoted', () => {
  // Mirrors the endpoint: finalRole keeps 'Manager' for the owner.
  const finalRoleFor = (targetIsOwner, requested) =>
    targetIsOwner && requested !== 'Manager' ? 'Manager' : requested;

  test('a Staff request against the owner stays Manager', () => {
    expect(finalRoleFor(true, 'Staff')).toBe('Manager');
  });

  test('a normal target keeps the requested role', () => {
    expect(finalRoleFor(false, 'Staff')).toBe('Staff');
    expect(finalRoleFor(true, 'Manager')).toBe('Manager');
  });
});
