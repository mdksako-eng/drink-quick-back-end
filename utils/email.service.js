const sgMail = require('@sendgrid/mail');
sgMail.setApiKey(process.env.SENDGRID_API_KEY);
const winston = require('winston');

const logger = winston.createLogger({
    level: 'info',
    format: winston.format.combine(winston.format.timestamp(), winston.format.json()),
    transports: [new winston.transports.File({ filename: 'logs/email.log' })],
});

const sendEmail = async (to, subject, html) => {
  try {
    const msg = {
      to,
      from: {
        email: process.env.EMAIL_FROM || 'm.derick@africet.org',
        name: 'Drink Quick Cal'
      },
      subject,
      html,
    };
    await sgMail.send(msg);
    logger.info('Email sent', { to, subject });
    return { success: true };
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
        <p style="color:#888;font-size:12px;">This link expires in 30 minutes.</p>
        <div style="background:#FFF8E1;border-left:4px solid #FFA000;padding:12px;border-radius:5px;font-size:12px;color:#8B6914;">
          ⚠️ If you didn't create this account, please ignore this email.
        </div>
      </div>
    </div>`;
  
  return await sendEmail(userEmail, '✅ Verify Your Email - Drink Quick Cal', html);
};

module.exports = { sendResetCodeEmail, sendWelcomeEmail, sendVerificationEmail };
