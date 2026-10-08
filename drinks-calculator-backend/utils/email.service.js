// Email goes through Resend (https://resend.com), over its REST API with the
// built-in fetch — so this file needs no email SDK and no extra dependency.
//
// Required env vars:
//   RESEND_API_KEY  your key (re_...)                     — without it, sending fails loudly
//   EMAIL_FROM      a sender on a domain verified in Resend, e.g.
//                   "Drink Quick Cal <notifications@yourdomain.com>"
const winston = require('winston');

const logger = winston.createLogger({
    level: 'info',
    format: winston.format.combine(winston.format.timestamp(), winston.format.json()),
    transports: [new winston.transports.File({ filename: 'logs/email.log' })],
});

const RESEND_ENDPOINT = 'https://api.resend.com/emails';
const RESEND_API_KEY = process.env.RESEND_API_KEY || '';
// Resend only accepts a sender on a domain you have verified there. Until that is
// done, 'onboarding@resend.dev' works but only delivers to your own account address.
const EMAIL_FROM = process.env.EMAIL_FROM || 'Drink Quick Cal <onboarding@resend.dev>';

/** Whether email can be sent at all — surfaced at startup so it cannot surprise us. */
const isEmailConfigured = () => Boolean(RESEND_API_KEY);

/**
 * The exact body Resend expects. Pure, so the request shape is testable.
 * @param {object} params { to, subject, html, from }
 * @returns {{from: string, to: string[], subject: string, html: string}}
 */
const buildEmailPayload = ({ to, subject, html, from }) => ({
  from: from || EMAIL_FROM,
  // Resend takes an array; a single address is normalised to one so a stray comma
  // can never turn one recipient into several.
  to: Array.isArray(to) ? to : [String(to)],
  subject: String(subject || ''),
  html: String(html || ''),
});

/** Send one email through Resend. Throws on failure — a silent drop is worse. */
const sendEmail = async (to, subject, html) => {
  if (!RESEND_API_KEY) {
    throw new Error('RESEND_API_KEY is not set — cannot send email');
  }
  try {
    const response = await fetch(RESEND_ENDPOINT, {
      method: 'POST',
      headers: {
        Authorization: `Bearer ${RESEND_API_KEY}`,
        'Content-Type': 'application/json',
      },
      body: JSON.stringify(buildEmailPayload({ to, subject, html })),
    });

    const data = await response.json().catch(() => ({}));
    if (!response.ok) {
      throw new Error(data.message || data.error || `Resend HTTP ${response.status}`);
    }

    logger.info('Email sent', { to, subject, id: data.id });
    return { success: true, id: data.id };
  } catch (error) {
    logger.error('Email failed', { to, error: error.message });
    throw new Error('Failed to send email: ' + error.message);
  }
};

// Reset code email
const sendResetCodeEmail = async (userEmail, code, username) => {
  const html = `
    <div style="font-family:Arial;max-width:500px;margin:0 auto;background:white;border-radius:15px;overflow:hidden;box-shadow:0 4px 15px rgba(0,0,0,0.1);">
      <div style="background:linear-gradient(135deg,#667EEA,#764BA2);padding:30px;text-align:center;">
        <h1 style="color:white;margin:0;">🍹 Drink Quick Cal</h1>
        <p style="color:rgba(255,255,255,0.8);">Password Reset Code</p>
      </div>
      <div style="padding:30px;">
        <h2>Hello ${username || 'there'}!</h2>
        <p>Use this code to reset your password:</p>
        <div style="background:#667EEA;color:white;font-size:36px;font-weight:bold;text-align:center;padding:20px;border-radius:10px;letter-spacing:12px;margin:20px 0;">${code}</div>
        <p style="text-align:center;color:#888;">⏰ Expires in 10 minutes</p>
        <div style="background:#FFF8E1;border-left:4px solid #FFA000;padding:12px;border-radius:5px;font-size:12px;color:#8B6914;">
          ⚠️ If you didn't request this, ignore this email.
        </div>
      </div>
    </div>`;
  return await sendEmail(userEmail, '🔑 Password Reset Code', html);
};

// Welcome email
const sendWelcomeEmail = async (userEmail, username) => {
  const html = `
    <div style="font-family:Arial;max-width:500px;margin:0 auto;background:white;border-radius:15px;overflow:hidden;box-shadow:0 4px 15px rgba(0,0,0,0.1);">
      <div style="background:linear-gradient(135deg,#38b000,#16a753);padding:30px;text-align:center;">
        <h1 style="color:white;margin:0;">🍹 Welcome!</h1>
      </div>
      <div style="padding:30px;">
        <h2>Hello ${username}! 🎉</h2>
        <p>Your Drink Quick Cal account is ready!</p>
      </div>
    </div>`;
  return await sendEmail(userEmail, '🎉 Welcome to Drink Quick Cal!', html);
};

// ============================================================
// EMAIL VERIFICATION (Link only, tap to verify)
// ============================================================
const sendVerificationEmail = async (userEmail, code, username) => {
  const verifyUrl = `https://drink-quick-cal-kja1.onrender.com/api/auth/confirm-email?email=${encodeURIComponent(userEmail)}&code=${code}`;
  
  const html = `
    <div style="font-family:Arial;max-width:500px;margin:0 auto;background:white;border-radius:15px;overflow:hidden;box-shadow:0 4px 15px rgba(0,0,0,0.1);">
      <div style="background:linear-gradient(135deg,#667EEA,#764BA2);padding:30px;text-align:center;">
        <h1 style="color:white;margin:0;">🍹 Drink Quick Cal</h1>
        <p style="color:rgba(255,255,255,0.8);">Verify Your Email Address</p>
      </div>
      <div style="padding:30px;">
        <h2>Hello ${username || 'there'}! 👋</h2>
        <p>Thank you for registering! Click the button below to verify your email address:</p>
        <div style="text-align:center;margin:30px 0;">
          <a href="${verifyUrl}" style="background:#667EEA;color:white;padding:15px 40px;border-radius:10px;text-decoration:none;font-weight:bold;font-size:16px;display:inline-block;">✅ Verify Email</a>
        </div>
        <p style="color:#888;font-size:12px;">This link expires in 10 minutes.</p>
        <div style="background:#FFF8E1;border-left:4px solid #FFA000;padding:12px;border-radius:5px;font-size:12px;color:#8B6914;">
          ⚠️ If you didn't create this account, please ignore this email.
        </div>
      </div>
    </div>`;
  
  return await sendEmail(userEmail, '✅ Verify Your Email - Drink Quick Cal', html);
};

// ============================================================
// COMPANY JOIN REQUEST — verification code sent to the OWNER
// ============================================================
const sendJoinRequestEmail = async (ownerEmail, ownerName, requesterName, companyName, code, role) => {
  const html = `
    <div style="font-family:Arial;max-width:500px;margin:0 auto;background:white;border-radius:15px;overflow:hidden;box-shadow:0 4px 15px rgba(0,0,0,0.1);">
      <div style="background:linear-gradient(135deg,#FF9800,#F57C00);padding:30px;text-align:center;">
        <h1 style="color:white;margin:0;">🍹 Drink Quick Cal</h1>
        <p style="color:rgba(255,255,255,0.8);">Company Join Verification</p>
      </div>
      <div style="padding:30px;">
        <h2>Hello ${ownerName || 'there'}!</h2>
        <p><strong>${requesterName}</strong> wants to join your company <strong>${companyName}</strong> as <strong>${role}</strong>.</p>
        <p>Share nothing — just enter this code in the app to approve:</p>
        <div style="background:#FF9800;color:white;font-size:36px;font-weight:bold;text-align:center;padding:20px;border-radius:10px;letter-spacing:12px;margin:20px 0;">${code}</div>
        <p style="text-align:center;color:#888;">⏰ Expires in 15 minutes</p>
        <div style="background:#FFF8E1;border-left:4px solid #FFA000;padding:12px;border-radius:5px;font-size:12px;color:#8B6914;">
          ⚠️ If you don't recognize this request, reject it in the app — the pending account will be deleted.
        </div>
      </div>
    </div>`;
  return await sendEmail(ownerEmail, '🔐 Verify New Member - Drink Quick Cal', html);
};

// Support report (bug / complaint) forwarded to the support inbox.
const sendSupportReportEmail = async ({ to, subject, html }) => sendEmail(to, subject, html);

module.exports = { sendResetCodeEmail, sendWelcomeEmail, sendVerificationEmail, sendJoinRequestEmail, sendSupportReportEmail, sendEmail, buildEmailPayload, isEmailConfigured };
