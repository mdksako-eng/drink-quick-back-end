// backend/tests/email_resend.test.js
// Resend replaced SendGrid, so the one thing worth pinning is the exact request
// shape Resend accepts — and that a missing key fails loudly instead of silently
// dropping a password-reset code.
const { buildEmailPayload, isEmailConfigured } = require('../utils/email.service');

describe('email.service (Resend)', () => {
  test('wraps a single recipient in the array Resend expects', () => {
    const payload = buildEmailPayload({ to: 'owner@bar.cm', subject: 'Hi', html: '<p>Hi</p>' });
    expect(payload.to).toEqual(['owner@bar.cm']);
  });

  test('keeps an explicit list of recipients', () => {
    const payload = buildEmailPayload({ to: ['a@x.cm', 'b@x.cm'], subject: 's', html: 'h' });
    expect(payload.to).toEqual(['a@x.cm', 'b@x.cm']);
  });

  test('uses EMAIL_FROM as the default sender', () => {
    const payload = buildEmailPayload({ to: 'a@x.cm', subject: 's', html: 'h' });
    expect(payload.from).toBe(process.env.EMAIL_FROM || 'Drink Quick Cal <onboarding@resend.dev>');
    expect(payload.from).toContain('@');
  });

  test('an explicit from wins over the default', () => {
    const payload = buildEmailPayload({
      to: 'a@x.cm', subject: 's', html: 'h', from: 'Support <support@x.cm>',
    });
    expect(payload.from).toBe('Support <support@x.cm>');
  });

  test('never sends undefined subject or html', () => {
    const payload = buildEmailPayload({ to: 'a@x.cm' });
    expect(payload.subject).toBe('');
    expect(payload.html).toBe('');
  });

  test('reports whether a key is configured', () => {
    expect(typeof isEmailConfigured()).toBe('boolean');
    expect(isEmailConfigured()).toBe(Boolean(process.env.RESEND_API_KEY));
  });
});
