// backend/routes/support.routes.js
// Bug reports and complaints from the people actually using the app. Mounted at
// /api/support.
//
// Two things happen with every report, on purpose:
//   1. it is STORED, so it can be listed, searched and marked resolved later;
//   2. it is EMAILED to the support address, so it is acted on immediately instead
//      of waiting for someone to open a dashboard.
// Storing happens first: if email fails, the report is not lost.
const express = require('express');
const router = express.Router();
const { getSessionUser } = require('../middleware/sessionAuth');
const supportReport = require('../utils/supportReport');
const emailService = require('../utils/email.service');

/** Where reports are sent. Configurable on Render, so no code change is needed. */
const SUPPORT_EMAIL = process.env.SUPPORT_EMAIL || 'mbundaderick@gmail.com';

async function requireSessionUser(req) {
  const authHeader = req.headers.authorization;
  const token =
    authHeader && authHeader.startsWith('Bearer ') ? authHeader.split(' ')[1] : null;
  return getSessionUser(req.db, token);
}

// ============================================================
// 📨 POST a bug report or complaint
// ============================================================
router.post('/reports', async (req, res) => {
  try {
    const user = await requireSessionUser(req);
    if (!user) {
      return res.status(401).json({ success: false, error: 'Invalid or expired session' });
    }

    const { category, subject, message, context } = req.body || {};
    const check = supportReport.validateReport({ category, subject, message });
    if (!check.ok) {
      return res.status(400).json({ success: false, error: check.reason, code: check.reason });
    }

    const reference = supportReport.newReference(user.company_id, check.value.category);
    const cleanContext = supportReport.sanitizeContext(context);

    let companyName = '';
    if (user.company_id) {
      const company = await req.db.query('SELECT name FROM companies WHERE id = $1', [
        user.company_id,
      ]);
      companyName = company.rows[0] ? company.rows[0].name || '' : '';
    }

    await req.db.query(
      `INSERT INTO support_reports
         (reference, company_id, user_id, username, category, subject, message,
          context, app_version, platform, screen, status)
       VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10, $11, 'new')`,
      [
        reference,
        user.company_id || null,
        user.id || null,
        user.username || '',
        check.value.category,
        check.value.subject,
        check.value.message,
        JSON.stringify(cleanContext),
        cleanContext.appVersion || null,
        cleanContext.platform || null,
        cleanContext.screen || null,
      ]
    );

    // The email is a notification, not the record: a failure here must not fail the
    // request, because the report is already safely stored.
    try {
      const { subject: mailSubject, html } = supportReport.buildEmail({
        report: check.value,
        user,
        companyName,
        context: cleanContext,
        reference,
      });
      await emailService.sendSupportReportEmail({ to: SUPPORT_EMAIL, subject: mailSubject, html });
      console.log(`📨 Support report ${reference} stored and emailed (${check.value.category})`);
    } catch (mailError) {
      console.warn(`⚠️ Support report ${reference} stored but NOT emailed: ${mailError.message}`);
    }

    return res.json({ success: true, data: { reference, status: 'new' } });
  } catch (error) {
    console.error('POST /support/reports error:', error.message);
    res.status(500).json({ success: false, error: 'Internal server error' });
  }
});

module.exports = router;
