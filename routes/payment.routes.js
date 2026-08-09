// backend/routes/payment.routes.js
const express = require('express');
const router = express.Router();
const crypto = require('crypto');
const axios = require('axios');

// ============================================================
// 📦 CONFIGURATION
// ============================================================

// In-memory store for payment requests (use Redis in production)
const paymentRequests = new Map();

// MTN & Orange API endpoints
const MTN_API = {
  sandbox: 'https://sandbox.momodeveloper.mtn.com',
  production: 'https://ericssonbasicapi2.azure-api.net',
};

const ORANGE_API = {
  sandbox: 'https://api.sandbox.orange-money.com',
  production: 'https://api.orange-money.com',
};

// ============================================================
// 📦 HELPER FUNCTIONS
// ============================================================

function generateTransactionId() {
  return `txn_${Date.now()}_${crypto.randomBytes(8).toString('hex')}`;
}

function generateRequestToken() {
  return `req_${Date.now()}_${crypto.randomBytes(8).toString('hex')}`;
}

function validatePhoneNumber(phone, provider) {
  const digits = phone.replace(/\D/g, '');
  if (provider === 'mtn') {
    return /^(237)?(6[5789]|68[0-9])\d{7}$/.test(digits);
  } else if (provider === 'orange') {
    return /^(237)?(6[9]|69[0-9])\d{7}$/.test(digits);
  }
  return false;
}

// ============================================================
// 💰 GET Company Payment Settings
// ============================================================
router.get('/company-settings', async (req, res) => {
  try {
    const { companyId, role } = req.user;
    
    // ✅ Get company from database
    const result = await req.db.query(
      `SELECT 
        id,
        name,
        business_payments_enabled,
        mtn_enabled,
        orange_enabled,
        mtn_merchant_phone,
        orange_merchant_phone,
        mtn_api_key,
        mtn_secret_key,
        mtn_merchant_id,
        mtn_sandbox_mode,
        orange_api_key,
        orange_secret_key,
        orange_merchant_id,
        orange_sandbox_mode
      FROM companies WHERE id = $1`,
      [companyId]
    );

    if (result.rows.length === 0) {
      return res.status(404).json({ error: 'Company not found' });
    }

    const company = result.rows[0];
    const isManager = ['Manager', 'Administrator', 'Admin'].includes(role);

    // ✅ Build response based on role
    const response = {
      id: company.id,
      name: company.name,
      businessPaymentsEnabled: company.business_payments_enabled || false,
      mtnEnabled: company.mtn_enabled || false,
      orangeEnabled: company.orange_enabled || false,
    };

    // ✅ ONLY Managers/Admins get to see/edit payment settings
    if (isManager) {
      response.mtnMerchantPhone = company.mtn_merchant_phone || '';
      response.orangeMerchantPhone = company.orange_merchant_phone || '';
      response.mtnApiKey = company.mtn_api_key || '';
      response.mtnSecretKey = company.mtn_secret_key || '';
      response.mtnMerchantId = company.mtn_merchant_id || '';
      response.mtnSandboxMode = company.mtn_sandbox_mode || true;
      response.orangeApiKey = company.orange_api_key || '';
      response.orangeSecretKey = company.orange_secret_key || '';
      response.orangeMerchantId = company.orange_merchant_id || '';
      response.orangeSandboxMode = company.orange_sandbox_mode || true;
      response.isManager = true;
    } else {
      response.isManager = false;
      // ✅ Mask sensitive data for non-managers
      response.mtnMerchantPhone = '••••••••••';
      response.orangeMerchantPhone = '••••••••••';
      response.mtnApiKey = '••••••••••';
      response.mtnSecretKey = '••••••••••';
      response.mtnMerchantId = '••••••••••';
      response.orangeApiKey = '••••••••••';
      response.orangeSecretKey = '••••••••••';
      response.orangeMerchantId = '••••••••••';
    }

    res.json({
      success: true,
      data: response,
      role: role,
    });

  } catch (error) {
    console.error('Error fetching company settings:', error);
    res.status(500).json({ error: 'Internal server error' });
  }
});

// ============================================================
// 💾 UPDATE Company Payment Settings (Manager only)
// ============================================================
router.patch('/company-settings', async (req, res) => {
  try {
    const { companyId, role } = req.user;
    
    // ✅ Only Managers can update
    const isManager = ['Manager', 'Administrator', 'Admin'].includes(role);
    if (!isManager) {
      return res.status(403).json({ 
        error: 'Only managers can update payment settings' 
      });
    }

    const {
      businessPaymentsEnabled,
      mtnEnabled,
      orangeEnabled,
      mtnMerchantPhone,
      orangeMerchantPhone,
      mtnApiKey,
      mtnSecretKey,
      mtnMerchantId,
      mtnSandboxMode,
      orangeApiKey,
      orangeSecretKey,
      orangeMerchantId,
      orangeSandboxMode,
    } = req.body;

    // ✅ Build update query
    const updates = {};
    const values = [];
    let paramIndex = 1;

    // ✅ Only update fields that are provided
    if (businessPaymentsEnabled !== undefined) {
      updates.business_payments_enabled = businessPaymentsEnabled;
    }
    if (mtnEnabled !== undefined) {
      updates.mtn_enabled = mtnEnabled;
    }
    if (orangeEnabled !== undefined) {
      updates.orange_enabled = orangeEnabled;
    }
    if (mtnMerchantPhone !== undefined) {
      updates.mtn_merchant_phone = mtnMerchantPhone;
    }
    if (orangeMerchantPhone !== undefined) {
      updates.orange_merchant_phone = orangeMerchantPhone;
    }
    if (mtnApiKey !== undefined) {
      updates.mtn_api_key = mtnApiKey;
    }
    if (mtnSecretKey !== undefined) {
      updates.mtn_secret_key = mtnSecretKey;
    }
    if (mtnMerchantId !== undefined) {
      updates.mtn_merchant_id = mtnMerchantId;
    }
    if (mtnSandboxMode !== undefined) {
      updates.mtn_sandbox_mode = mtnSandboxMode;
    }
    if (orangeApiKey !== undefined) {
      updates.orange_api_key = orangeApiKey;
    }
    if (orangeSecretKey !== undefined) {
      updates.orange_secret_key = orangeSecretKey;
    }
    if (orangeMerchantId !== undefined) {
      updates.orange_merchant_id = orangeMerchantId;
    }
    if (orangeSandboxMode !== undefined) {
      updates.orange_sandbox_mode = orangeSandboxMode;
    }
    
    updates.updated_at = new Date();

    // ✅ Build SET clause
    const setClauses = [];
    for (const [key, value] of Object.entries(updates)) {
      setClauses.push(`${key} = $${paramIndex}`);
      values.push(value);
      paramIndex++;
    }

    values.push(companyId);

    await req.db.query(
      `UPDATE companies SET ${setClauses.join(', ')} WHERE id = $${paramIndex}`,
      values
    );

    res.json({ 
      success: true, 
      message: 'Payment settings updated successfully' 
    });

  } catch (error) {
    console.error('Error updating company settings:', error);
    res.status(500).json({ error: 'Internal server error' });
  }
});

// ============================================================
// 💰 INITIATE PAYMENT
// ============================================================
router.post('/payment/initiate', async (req, res) => {
  try {
    const { companyId, userId, role } = req.user;
    const { amount, customerPhone, paymentMethod, orderId } = req.body;

    // ✅ Validate input
    if (!amount || amount <= 0) {
      return res.status(400).json({ error: 'Invalid amount' });
    }
    if (!customerPhone) {
      return res.status(400).json({ error: 'Customer phone is required' });
    }
    if (!paymentMethod || !['mtn', 'orange'].includes(paymentMethod)) {
      return res.status(400).json({ error: 'Invalid payment method' });
    }

    // ✅ Validate phone number format
    if (!validatePhoneNumber(customerPhone, paymentMethod)) {
      return res.status(400).json({ 
        error: `Invalid ${paymentMethod} phone number. Format: 237XXXXXXXXX` 
      });
    }

    // ✅ Get company credentials
    const result = await req.db.query(
      `SELECT 
        name,
        business_payments_enabled,
        mtn_enabled,
        orange_enabled,
        mtn_merchant_phone,
        orange_merchant_phone,
        mtn_api_key,
        mtn_secret_key,
        mtn_merchant_id,
        mtn_sandbox_mode,
        orange_api_key,
        orange_secret_key,
        orange_merchant_id,
        orange_sandbox_mode
      FROM companies WHERE id = $1`,
      [companyId]
    );

    if (result.rows.length === 0) {
      return res.status(404).json({ error: 'Company not found' });
    }

    const company = result.rows[0];

    // ✅ Check if business payments are enabled
    if (!company.business_payments_enabled) {
      return res.status(400).json({ 
        error: 'Business payments are not enabled for this company' 
      });
    }

    // ✅ Check if payment method is enabled
    if (paymentMethod === 'mtn' && !company.mtn_enabled) {
      return res.status(400).json({ 
        error: 'MTN Mobile Money is not enabled' 
      });
    }
    if (paymentMethod === 'orange' && !company.orange_enabled) {
      return res.status(400).json({ 
        error: 'Orange Money is not enabled' 
      });
    }

    // ✅ Check if merchant has credentials
    if (paymentMethod === 'mtn') {
      if (!company.mtn_api_key || !company.mtn_secret_key || !company.mtn_merchant_id) {
        return res.status(400).json({ 
          error: 'MTN merchant is not fully configured. Please contact your manager.' 
        });
      }
    } else if (paymentMethod === 'orange') {
      if (!company.orange_api_key || !company.orange_secret_key || !company.orange_merchant_id) {
        return res.status(400).json({ 
          error: 'Orange merchant is not fully configured. Please contact your manager.' 
        });
      }
    }

    // ✅ Generate transaction ID
    const transactionId = generateTransactionId();

    // ✅ Store payment request in memory (use Redis in production)
    paymentRequests.set(transactionId, {
      companyId,
      userId,
      orderId,
      amount,
      customerPhone,
      paymentMethod,
      companyName: company.name,
      status: 'pending',
      createdAt: Date.now(),
    });

    // ✅ Save transaction to database
    await req.db.query(
      `INSERT INTO payment_transactions 
       (order_id, company_id, customer_phone, amount, payment_method, transaction_id, status)
       VALUES ($1, $2, $3, $4, $5, $6, $7)`,
      [orderId, companyId, customerPhone, amount, paymentMethod, transactionId, 'pending']
    );

    // ✅ Log the payment initiation
    console.log(`📲 Payment initiated:`);
    console.log(`   Company: ${company.name}`);
    console.log(`   Amount: ${amount} XAF`);
    console.log(`   Customer: ${customerPhone}`);
    console.log(`   Method: ${paymentMethod}`);
    console.log(`   Transaction: ${transactionId}`);

    // ✅ In production, you would call the actual payment API here
    // For now, we'll simulate the request
    
    // ✅ Return success with transaction ID
    res.json({
      success: true,
      transactionId: transactionId,
      status: 'pending',
      message: `Payment request sent to ${customerPhone}. Please check your phone.`,
      expiresIn: 300, // 5 minutes
    });

  } catch (error) {
    console.error('Payment initiation error:', error);
    res.status(500).json({ 
      success: false, 
      error: 'Payment initiation failed' 
    });
  }
});

// ============================================================
// 🔍 CHECK PAYMENT STATUS
// ============================================================
router.get('/payment/status/:transactionId', async (req, res) => {
  try {
    const { transactionId } = req.params;
    const { companyId } = req.user;

    // ✅ Get from database
    const result = await req.db.query(
      `SELECT status, error_message, confirmed_at, created_at
       FROM payment_transactions 
       WHERE transaction_id = $1 AND company_id = $2`,
      [transactionId, companyId]
    );

    if (result.rows.length === 0) {
      return res.status(404).json({ 
        success: false, 
        error: 'Transaction not found' 
      });
    }

    const transaction = result.rows[0];

    // ✅ In production: Check with actual payment provider
    // For testing: Auto-complete after 15 seconds
    if (transaction.status === 'pending') {
      const created = new Date(transaction.created_at);
      const elapsed = Date.now() - created.getTime();
      
      // ✅ Auto-complete for testing (remove in production)
      if (elapsed > 15000) { // 15 seconds
        await req.db.query(
          `UPDATE payment_transactions 
           SET status = 'completed', confirmed_at = NOW() 
           WHERE transaction_id = $1`,
          [transactionId]
        );
        
        // ✅ Update in-memory store
        const payment = paymentRequests.get(transactionId);
        if (payment) {
          payment.status = 'completed';
          payment.confirmedAt = new Date();
        }
        
        console.log(`✅ Payment ${transactionId} auto-completed after ${elapsed}ms`);
        
        return res.json({
          success: true,
          status: 'completed',
          confirmedAt: new Date().toISOString(),
        });
      }
      
      // ✅ Check if expired (5 minutes)
      if (elapsed > 300000) { // 5 minutes
        await req.db.query(
          `UPDATE payment_transactions 
           SET status = 'expired', error_message = 'Payment request expired' 
           WHERE transaction_id = $1`,
          [transactionId]
        );
        
        const payment = paymentRequests.get(transactionId);
        if (payment) {
          payment.status = 'expired';
        }
        
        return res.json({
          success: true,
          status: 'expired',
          errorMessage: 'Payment request expired',
        });
      }
    }

    res.json({
      success: true,
      status: transaction.status,
      errorMessage: transaction.error_message,
      confirmedAt: transaction.confirmed_at,
    });

  } catch (error) {
    console.error('Payment status check error:', error);
    res.status(500).json({ 
      success: false, 
      error: 'Failed to check payment status' 
    });
  }
});

// ============================================================
// ❌ CANCEL PAYMENT
// ============================================================
router.post('/payment/cancel', async (req, res) => {
  try {
    const { transactionId } = req.body;
    const { companyId } = req.user;

    // ✅ Update transaction status in database
    const result = await req.db.query(
      `UPDATE payment_transactions 
       SET status = 'cancelled', error_message = 'Cancelled by user' 
       WHERE transaction_id = $1 AND company_id = $2 AND status = 'pending'
       RETURNING *`,
      [transactionId, companyId]
    );

    if (result.rows.length === 0) {
      return res.status(404).json({ 
        success: false, 
        error: 'Transaction not found or already completed' 
      });
    }

    // ✅ Remove from memory store
    const payment = paymentRequests.get(transactionId);
    if (payment) {
      payment.status = 'cancelled';
    }

    console.log(`❌ Payment ${transactionId} cancelled by user`);

    res.json({
      success: true,
      message: 'Payment cancelled',
    });

  } catch (error) {
    console.error('Payment cancellation error:', error);
    res.status(500).json({ 
      success: false, 
      error: 'Failed to cancel payment' 
    });
  }
});

// ============================================================
// 📊 GET PAYMENT HISTORY (Manager only)
// ============================================================
router.get('/payment/history', async (req, res) => {
  try {
    const { companyId, role } = req.user;
    
    // ✅ Only Managers can view payment history
    const isManager = ['Manager', 'Administrator', 'Admin'].includes(role);
    if (!isManager) {
      return res.status(403).json({ 
        error: 'Only managers can view payment history' 
      });
    }

    const { limit = 50, offset = 0, status } = req.query;

    let query = `
      SELECT 
        id,
        order_id,
        customer_phone,
        amount,
        payment_method,
        status,
        transaction_id,
        created_at,
        confirmed_at,
        error_message
      FROM payment_transactions 
      WHERE company_id = $1
    `;
    const params = [companyId];
    let paramIndex = 2;

    if (status) {
      query += ` AND status = $${paramIndex}`;
      params.push(status);
      paramIndex++;
    }

    query += ` ORDER BY created_at DESC LIMIT $${paramIndex} OFFSET $${paramIndex + 1}`;
    params.push(parseInt(limit), parseInt(offset));

    const result = await req.db.query(query, params);

    // ✅ Get total count
    const countResult = await req.db.query(
      `SELECT COUNT(*) FROM payment_transactions WHERE company_id = $1`,
      [companyId]
    );

    res.json({
      success: true,
      data: result.rows,
      total: parseInt(countResult.rows[0].count),
      limit: parseInt(limit),
      offset: parseInt(offset),
    });

  } catch (error) {
    console.error('Payment history error:', error);
    res.status(500).json({ error: 'Internal server error' });
  }
});

// ============================================================
// 📊 GET PAYMENT STATS (Manager only)
// ============================================================
router.get('/payment/stats', async (req, res) => {
  try {
    const { companyId, role } = req.user;
    
    // ✅ Only Managers can view stats
    const isManager = ['Manager', 'Administrator', 'Admin'].includes(role);
    if (!isManager) {
      return res.status(403).json({ 
        error: 'Only managers can view payment stats' 
      });
    }

    const { period = 'today' } = req.query;

    let dateFilter = '';
    if (period === 'today') {
      dateFilter = "AND created_at::date = CURRENT_DATE";
    } else if (period === 'week') {
      dateFilter = "AND created_at >= CURRENT_DATE - INTERVAL '7 days'";
    } else if (period === 'month') {
      dateFilter = "AND created_at >= CURRENT_DATE - INTERVAL '30 days'";
    }

    const result = await req.db.query(`
      SELECT 
        COUNT(*) as total_transactions,
        COUNT(CASE WHEN status = 'completed' THEN 1 END) as completed,
        COUNT(CASE WHEN status = 'pending' THEN 1 END) as pending,
        COUNT(CASE WHEN status = 'failed' THEN 1 END) as failed,
        COUNT(CASE WHEN status = 'cancelled' THEN 1 END) as cancelled,
        COALESCE(SUM(CASE WHEN status = 'completed' THEN amount ELSE 0 END), 0) as total_amount,
        COALESCE(SUM(CASE WHEN status = 'completed' AND payment_method = 'mtn' THEN amount ELSE 0 END), 0) as mtn_amount,
        COALESCE(SUM(CASE WHEN status = 'completed' AND payment_method = 'orange' THEN amount ELSE 0 END), 0) as orange_amount
      FROM payment_transactions 
      WHERE company_id = $1 ${dateFilter}
    `, [companyId]);

    res.json({
      success: true,
      data: result.rows[0],
      period: period,
    });

  } catch (error) {
    console.error('Payment stats error:', error);
    res.status(500).json({ error: 'Internal server error' });
  }
});

// ============================================================
// 🔄 WEBHOOK for payment confirmation (from MTN/Orange)
// ============================================================
router.post('/payment/webhook', async (req, res) => {
  try {
    const { transactionId, status, reference, errorMessage } = req.body;

    console.log(`📨 Webhook received for ${transactionId}: ${status}`);

    // ✅ Find the transaction
    const result = await req.db.query(
      `SELECT id, order_id, company_id FROM payment_transactions 
       WHERE transaction_id = $1`,
      [transactionId]
    );

    if (result.rows.length === 0) {
      console.log(`⚠️ Transaction ${transactionId} not found`);
      return res.status(404).json({ error: 'Transaction not found' });
    }

    const transaction = result.rows[0];

    // ✅ Update transaction status
    await req.db.query(
      `UPDATE payment_transactions 
       SET status = $1, confirmed_at = $2, error_message = $3
       WHERE transaction_id = $4`,
      [
        status === 'completed' ? 'completed' : 'failed',
        status === 'completed' ? new Date() : null,
        errorMessage || null,
        transactionId,
      ]
    );

    // ✅ Update in-memory store
    const payment = paymentRequests.get(transactionId);
    if (payment) {
      payment.status = status === 'completed' ? 'completed' : 'failed';
      if (status === 'completed') {
        payment.confirmedAt = new Date();
      }
    }

    // ✅ If payment was successful, you could trigger order completion here
    if (status === 'completed') {
      console.log(`✅ Payment ${transactionId} confirmed via webhook`);
      // TODO: Trigger order completion, inventory update, etc.
    }

    res.json({ success: true });

  } catch (error) {
    console.error('Webhook error:', error);
    res.status(500).json({ error: 'Internal server error' });
  }
});

// ============================================================
// 🔄 HEALTH CHECK
// ============================================================
router.get('/payment/health', (req, res) => {
  res.json({
    status: 'ok',
    timestamp: new Date().toISOString(),
    pendingTransactions: paymentRequests.size,
  });
});

module.exports = router;
