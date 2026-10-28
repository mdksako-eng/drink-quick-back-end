/**
 * Who may read or change a company's CamerPay credentials - no database required.
 *
 * A CamerPay token can move that company's money, so the rule is enforced on the
 * SERVER, from the session - never by hiding the button in the app. Staff must be
 * refused. These guards lock the allow-list and the refusals so a later refactor
 * cannot quietly widen access.
 *
 * Live roles measured 2026-10-28: Manager 8, Staff 3, Customer 2, Administrator 1.
 *
 * Run with: npm test
 */
const fs = require('fs');
const path = require('path');

const root = path.join(__dirname, '..');
const read = (rel) => fs.readFileSync(path.join(root, rel), 'utf8');

describe('payment credential authorization', () => {
  const routes = read('routes/payment.routes.js');

  test('the allow-list covers owner/manager/admin and excludes staff and customers', () => {
    const start = routes.indexOf('function canManagePaymentSettings');
    expect(start).toBeGreaterThan(-1);
    const block = routes.slice(start, start + 220);

    expect(block).toContain("'Manager'");
    expect(block).toContain("'Owner'");
    expect(block).not.toContain("'Staff'");
    expect(block).not.toContain("'Customer'");
  });

  test('reading the CamerPay settings is refused outside that list', () => {
    expect(routes).toContain('canManagePaymentSettings(user.role)');
    expect(routes).toContain('res.status(403)');
  });

  test('changing the credentials is refused outside that list', () => {
    expect(routes).toContain("Only managers can change payment settings");
    expect(routes).toContain("Only managers can update payment settings");
  });

  test('the role comes from the session, never from the request body', () => {
    expect(routes).toContain('await requireSessionUser(req)');
    expect(routes).not.toMatch(/req\.body\.(role|userRole|isOwner)/);
  });

  test('a credential is refused rather than stored in the clear without the vault key', () => {
    // credentialVault.loadKey() throws when PAYMENT_CREDENTIALS_KEY is missing and
    // the route answers 400 with that instruction, so there is no plaintext path.
    expect(routes).toContain('PAYMENT_CREDENTIALS_KEY');
    const vault = read('utils/credentialVault.js');
    expect(vault).toContain('refusing to handle payment credentials');
  });

  test('the app also hides the payment cards from staff', () => {
    const screen = fs.readFileSync(
      path.join(root, '..', 'lib', 'screens', 'storage_settings_screen.dart'),
      'utf8'
    );
    expect(screen).toContain('if (!isStaff) ...[');
  });
});
