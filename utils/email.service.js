const nodemailer = require('nodemailer');
const winston = require('winston');

const logger = winston.createLogger({
    level: 'info',
    format: winston.format.combine(
        winston.format.timestamp(),
        winston.format.json()
    ),
    transports: [
        new winston.transports.File({ filename: 'logs/email.log' }),
    ],
});

// Create transporter
const createTransporter = () => {
    return nodemailer.createTransport({
        host: process.env.EMAIL_HOST,
        port: process.env.EMAIL_PORT,
        secure: process.env.EMAIL_PORT === 465,
        auth: {
            user: process.env.EMAIL_USER,
            pass: process.env.EMAIL_PASS,
        },
    });
};

// Email templates
const emailTemplates = {
        passwordReset: (name, resetLink) => ({
            subject: 'Drinks Calculator - Password Reset',
            html: `
      <!DOCTYPE html>
      <html>
      <head>
        <style>
          body { font-family: Arial, sans-serif; line-height: 1.6; color: #333; margin: 0; padding: 0; }
          .container { max-width: 600px; margin: 0 auto; padding: 20px; }
          .header { background: linear-gradient(135deg, #667eea 0%, #764ba2 100%); color: white; padding: 30px; text-align: center; border-radius: 10px 10px 0 0; }
          .content { background: #f9f9f9; padding: 30px; border-radius: 0 0 10px 10px; }
          .button { display: inline-block; background: #667eea; color: white; padding: 12px 30px; text-decoration: none; border-radius: 5px; font-weight: bold; margin: 20px 0; }
          .footer { margin-top: 30px; padding-top: 20px; border-top: 1px solid #ddd; color: #666; font-size: 12px; }
          .logo { font-size: 24px; font-weight: bold; color: white; }
          .code { background: #f0f0f0; padding: 10px; border-radius: 5px; font-family: monospace; word-break: break-all; margin: 20px 0; }
        </style>
      </head>
      <body>
        <div class="container">
          <div class="header">
            <div class="logo">🍻 Drinks Calculator</div>
            <h1>Password Reset Request</h1>
          </div>
          <div class="content">
            <h2>Hello ${name},</h2>
            <p>We received a request to reset your password for your Drinks Calculator account.</p>
            <p>Click the button below to reset your password:</p>
            <p style="text-align: center;">
              <a href="${resetLink}" class="button">Reset Password</a>
            </p>
            <p>This link will expire in 1 hour. If you didn't request a password reset, please ignore this email.</p>
            <p>If the button doesn't work, copy and paste this link into your browser:</p>
            <div class="code">${resetLink}</div>
            <div class="footer">
              <p>This email was sent by Drinks Calculator. Please do not reply to this email.</p>
              <p>If you need assistance, contact our support team.</p>
            </div>
          </div>
        </div>
      </body>
      </html>
    `,
        }),

        passwordResetSuccess: (name) => ({
            subject: 'Drinks Calculator - Password Reset Successful',
            html: `
      <!DOCTYPE html>
      <html>
      <head>
        <style>
          body { font-family: Arial, sans-serif; line-height: 1.6; color: #333; margin: 0; padding: 0; }
          .container { max-width: 600px; margin: 0 auto; padding: 20px; }
          .header { background: linear-gradient(135deg, #38b000 0%, #16a753 100%); color: white; padding: 30px; text-align: center; border-radius: 10px 10px 0 0; }
          .content { background: #f9f9f9; padding: 30px; border-radius: 0 0 10px 10px; }
          .success-icon { font-size: 48px; color: #38b000; text-align: center; }
          .footer { margin-top: 30px; padding-top: 20px; border-top: 1px solid #ddd; color: #666; font-size: 12px; }
        </style>
      </head>
      <body>
        <div class="container">
          <div class="header">
            <h1>✅ Password Reset Successful</h1>
          </div>
          <div class="content">
            <div class="success-icon">✓</div>
            <h2>Hello ${name},</h2>
            <p>Your password has been successfully reset.</p>
            <p>If you did not initiate this password reset, please contact our support team immediately.</p>
            <p>For security reasons, we recommend:</p>
            <ul>
              <li>Using a strong, unique password</li>
              <li>Enabling two-factor authentication if available</li>
              <li>Not sharing your password with anyone</li>
            </ul>
            <div class="footer">
              <p>This email was sent by Drinks Calculator.</p>
            </div>
          </div>
        </div>
      </body>
      </html>
    `,
        }),

        welcome: (name, username) => ({
            subject: 'Welcome to Drinks Calculator! 🍻',
            html: `
      <!DOCTYPE html>
      <html>
      <head>
        <style>
          body { font-family: Arial, sans-serif; line-height: 1.6; color: #333; margin: 0; padding: 0; }
          .container { max-width: 600px; margin: 0 auto; padding: 20px; }
          .header { background: linear-gradient(135deg, #667eea 0%, #764ba2 100%); color: white; padding: 30px; text-align: center; border-radius: 10px 10px 0 0; }
          .content { background: #f9f9f9; padding: 30px; border-radius: 0 0 10px 10px; }
          .feature { background: white; padding: 15px; margin: 10px 0; border-radius: 5px; border-left: 4px solid #667eea; }
          .footer { margin-top: 30px; padding-top: 20px; border-top: 1px solid #ddd; color: #666; font-size: 12px; }
        </style>
      </head>
      <body>
        <div class="container">
          <div class="header">
            <h1>Welcome to Drinks Calculator! 🍻</h1>
          </div>
          <div class="content">
            <h2>Hello ${name},</h2>
            <p>Thank you for registering with Drinks Calculator. We're excited to have you on board!</p>
            <p>Your account details:</p>
            <ul>
              <li><strong>Username:</strong> ${username}</li>
              <li><strong>Account Type:</strong> Customer</li>
              <li><strong>Registration Date:</strong> ${new Date().toLocaleDateString()}</li>
            </ul>
            <p>Get started with these features:</p>
            <div class="feature">
              <strong>📊 Drink Management</strong>
              <p>Add, edit, and organize your drinks inventory</p>
            </div>
            <div class="feature">
              <strong>💰 Order Processing</strong>
              <p>Process orders and generate invoices</p>
            </div>
            <div class="feature">
              <strong>📈 Sales Analytics</strong>
              <p>Track your sales and performance</p>
            </div>
            <div class="feature">
              <strong>📱 Offline Support</strong>
              <p>Work without internet connection</p>
            </div>
            <p>Need help? Check out our documentation or contact support.</p>
            <div class="footer">
              <p>Cheers,<br>The Drinks Calculator Team</p>
            </div>
          </div>
        </div>
      </body>
      </html>
    `,
        }),

        orderConfirmation: (name, orderNumber, total, items) => ({
                    subject: `Order Confirmation #${orderNumber}`,
                    html: `
      <!DOCTYPE html>
      <html>
      <head>
        <style>
          body { font-family: Arial, sans-serif; line-height: 1.6; color: #333; margin: 0; padding: 0; }
          .container { max-width: 600px; margin: 0 auto; padding: 20px; }
          .header { background: linear-gradient(135deg, #4361ee 0%, #3a0ca3 100%); color: white; padding: 30px; text-align: center; border-radius: 10px 10px 0 0; }
          .content { background: #f9f9f9; padding: 30px; border-radius: 0 0 10px 10px; }
          .order-table { width: 100%; border-collapse: collapse; margin: 20px 0; }
          .order-table th { background: #4361ee; color: white; padding: 10px; text-align: left; }
          .order-table td { padding: 10px; border-bottom: 1px solid #ddd; }
          .total { font-size: 18px; font-weight: bold; color: #4361ee; text-align: right; }
          .footer { margin-top: 30px; padding-top: 20px; border-top: 1px solid #ddd; color: #666; font-size: 12px; }
        </style>
      </head>
      <body>
        <div class="container">
          <div class="header">
            <h1>Order Confirmation 🧾</h1>
            <p>Order #${orderNumber}</p>
          </div>
          <div class="content">
            <h2>Hello ${name},</h2>
            <p>Thank you for your order! Here are your order details:</p>
            <table class="order-table">
              <thead>
                <tr>
                  <th>Item</th>
                  <th>Quantity</th>
                  <th>Price</th>
                  <th>Total</th>
                </tr>
              </thead>
              <tbody>
                ${items.map(item => `
                  <tr>
                    <td>${item.name}</td>
                    <td>${item.quantity}</td>
                    <td>${item.price} Frs</td>
                    <td>${item.total} Frs</td>
                  </tr>
                `).join('')}
              </tbody>
            </table>
            <p class="total">Total Amount: ${total} Frs</p>
            <p>Your order has been processed successfully.</p>
            <div class="footer">
              <p>Thank you for choosing Drinks Calculator!</p>
            </div>
          </div>
        </div>
      </body>
      </html>
    `,
  }),

  passwordChanged: (name) => ({
    subject: 'Drinks Calculator - Password Changed',
    html: `
      <!DOCTYPE html>
      <html>
      <head>
        <style>
          body { font-family: Arial, sans-serif; line-height: 1.6; color: #333; margin: 0; padding: 0; }
          .container { max-width: 600px; margin: 0 auto; padding: 20px; }
          .header { background: linear-gradient(135deg, #4361ee 0%, #3a0ca3 100%); color: white; padding: 30px; text-align: center; border-radius: 10px 10px 0 0; }
          .content { background: #f9f9f9; padding: 30px; border-radius: 0 0 10px 10px; }
          .warning { background: #fff3cd; border: 1px solid #ffeaa7; padding: 15px; border-radius: 5px; margin: 20px 0; }
          .footer { margin-top: 30px; padding-top: 20px; border-top: 1px solid #ddd; color: #666; font-size: 12px; }
        </style>
      </head>
      <body>
        <div class="container">
          <div class="header">
            <h1>🔒 Password Changed</h1>
          </div>
          <div class="content">
            <h2>Hello ${name},</h2>
            <p>Your password has been successfully changed.</p>
            <div class="warning">
              <strong>Important Security Notice:</strong>
              <p>If you did not make this change, please contact our support team immediately.</p>
            </div>
            <p>For your security:</p>
            <ul>
              <li>Use a strong, unique password</li>
              <li>Never share your password</li>
              <li>Log out from shared devices</li>
              <li>Enable two-factor authentication if available</li>
            </ul>
            <div class="footer">
              <p>This email was sent by Drinks Calculator.</p>
            </div>
          </div>
        </div>
      </body>
      </html>
    `,
  }),
};

// Send email function
const sendEmail = async (to, subject, html, text = '') => {
  try {
    const transporter = createTransporter();

    const mailOptions = {
      from: process.env.EMAIL_FROM,
      to,
      subject,
      html,
      text: text || subject,
    };

    const info = await transporter.sendMail(mailOptions);
    
    logger.info('Email sent successfully', {
      to,
      subject,
      messageId: info.messageId,
    });

    return {
      success: true,
      messageId: info.messageId,
    };
  } catch (error) {
    logger.error('Failed to send email', {
      to,
      subject,
      error: error.message,
    });

    throw new Error(`Failed to send email: ${error.message}`);
  }
};

// Password reset email
const sendPasswordResetEmail = async (user, resetToken) => {
  try {
    const resetUrl = `${process.env.PASSWORD_RESET_URL}/${resetToken}`;
    const template = emailTemplates.passwordReset(user.username, resetUrl);

    return await sendEmail(
      user.email,
      template.subject,
      template.html
    );
  } catch (error) {
    throw error;
  }
};

// Password reset success email
const sendPasswordResetSuccessEmail = async (user) => {
  try {
    const template = emailTemplates.passwordResetSuccess(user.username);

    return await sendEmail(
      user.email,
      template.subject,
      template.html
    );
  } catch (error) {
    throw error;
  }
};

// Welcome email
const sendWelcomeEmail = async (user) => {
  try {
    const template = emailTemplates.welcome(user.username, user.username);

    return await sendEmail(
      user.email,
      template.subject,
      template.html
    );
  } catch (error) {
    throw error;
  }
};

// Order confirmation email
const sendOrderConfirmationEmail = async (user, order) => {
  try {
    const items = order.items.map(item => ({
      name: item.drinkName,
      quantity: item.quantity,
      price: item.pricePerUnit,
      total: item.totalPrice,
    }));

    const template = emailTemplates.orderConfirmation(
      user.username,
      order.orderNumber,
      order.totalAmount,
      items
    );

    return await sendEmail(
      user.email,
      template.subject,
      template.html
    );
  } catch (error) {
    throw error;
  }
};

// Password changed email
const sendPasswordChangedEmail = async (user) => {
  try {
    const template = emailTemplates.passwordChanged(user.username);

    return await sendEmail(
      user.email,
      template.subject,
      template.html
    );
  } catch (error) {
    throw error;
  }
};

module.exports = {
  sendEmail,
  sendPasswordResetEmail,
  sendPasswordResetSuccessEmail,
  sendWelcomeEmail,
  sendOrderConfirmationEmail,
  sendPasswordChangedEmail,
};