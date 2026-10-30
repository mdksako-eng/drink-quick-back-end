/**
 * Changing a company's CamerPay credential moves that company's money.
 * Pure rules + source guards - no database required.
 *
 * The threat: a manager session left open on a till (or a rogue manager) can replace
 * the token and send every future collection to another CamerPay account. Three
 * controls must stay in place - re-authentication for the token, a durable audit row,
 * and a notice to the owner - so this test fails if one of them is dropped.
 *
 * Run with: npm test
 */
const fs = require('fs');
const path = require('path');

const credentialChange = require('../utils/credentialChange');

const root = path.join(__dirname, '..');
const read = (rel) => fs.readFileSync(path.join(root, rel), 'utf8');

describe('what a credential change did', () => {
  test('describes it without ever carrying a value', () => {
    const detail = credentialChange.describeChange({
      tokenReplaced: true,
      secretReplaced: true,
      webhookRotated: true,
      enabled: true,
    });
    expect(detail).toBe(
      'api token replaced; webhook secret replaced; webhook token rotated; collection enabled'
    );
  });

  test('an enable/disable on its own is still described', () => {
    expect(credentialChange.describeChange({ enabled: false })).toBe('collection disabled');
  });

  test('nothing changed is said plainly', () => {
    expect(credentialChange.describeChange({})).toBe('no change');
  });
});

describe('which changes need extra care', () => {
  test('only a token redirects money', () => {
    expect(credentialChange.redirectsMoney({ tokenReplaced: true })).toBe(true);
    expect(credentialChange.redirectsMoney({ secretReplaced: true })).toBe(false);
    expect(credentialChange.redirectsMoney({ webhookRotated: true })).toBe(false);
    expect(credentialChange.redirectsMoney({})).toBe(false);
  });

  test('the owner is told about a token or secret change, not about a toggle', () => {
    expect(credentialChange.needsOwnerNotice({ tokenReplaced: true })).toBe(true);
    expect(credentialChange.needsOwnerNotice({ secretReplaced: true })).toBe(true);
    expect(credentialChange.needsOwnerNotice({ webhookRotated: true })).toBe(false);
    expect(credentialChange.needsOwnerNotice({ enabled: false })).toBe(false);
    expect(credentialChange.needsOwnerNotice({})).toBe(false);
  });
});

describe('the route keeps all three controls', () => {
  const routes = read('routes/payment.routes.js');

  test('a token change demands the actor password', () => {
    expect(routes).toContain('verifyActorPassword');
    expect(routes).toContain('redirectsMoney({ tokenReplaced: Boolean(newToken) })');
    expect(routes).toContain('reauthLimiter');
  });

  test('the password is checked with bcrypt, exactly like the login route', () => {
    expect(routes).toContain('bcrypt.compare');
    expect(routes).toContain('isBcryptHash');
    // One hashing path only: no second scheme, and the legacy plaintext row is
    // upgraded rather than kept.
    expect(routes).not.toContain('md5');
    expect(routes).not.toContain('sha1');
    expect(routes).toContain('bcrypt.hash(password, 10)');
  });

  test('re-auth failures answer with machine codes the app can translate', () => {
    for (const code of ['password_required', 'invalid_password', 'too_many_attempts']) {
      expect(routes).toContain(code);
    }
  });

  test('every change is audited', () => {
    expect(routes).toContain('auditLog.record');
    expect(routes).toContain('credentialChange.ACTIONS.CREDENTIAL_CHANGED');
  });

  test('the owner is emailed about a token or secret change', () => {
    expect(routes).toContain('notifyOwnerOfCredentialChange');
    expect(routes).toContain('sendPaymentCredentialChangedEmail');
    // Best effort: a dead mailer must not fail the change.
    expect(routes).toContain('Credential-change notice not sent');
  });

  test('the audit detail and the notice carry booleans, never the values', () => {
    const detail = routes.slice(routes.indexOf('credentialChange.describeChange'));
    const block = detail.slice(0, 400);
    expect(block).not.toContain('newToken:');
    expect(block).not.toContain('newSecret:');
    expect(block).not.toContain('currentPassword:');
  });

  test('the app asks for the password before sending a token', () => {
    const screen = read('../lib/screens/storage_settings_screen.dart');
    expect(screen).toContain('_promptCampayPassword');
    expect(screen).toContain('currentPassword: campayPassword');
    expect(screen).toContain('currentPassword: password');
  });
});
