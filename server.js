const express = require('express');
const cors = require('cors');
const path = require('path');
const { Pool } = require('pg');
require('dotenv').config();

const app = express();

// ========== EMAIL SERVICE ==========
const { sendResetCodeEmail, sendWelcomeEmail, sendVerificationEmail } = require('./utils/email.service');

// ========== POSTGRESQL SETUP ==========
console.log('🔌 Connecting to PostgreSQL (Neon)...');

const pool = new Pool({
  connectionString: process.env.DATABASE_URL,
  ssl: { 
    rejectUnauthorized: false 
  },
  connectionTimeoutMillis: 30000,
  idleTimeoutMillis: 60000,
  max: 10,
  keepAlive: true,
  keepAliveInitialDelayMillis: 10000
});

// Keep connection alive middleware
app.use(async (req, res, next) => {
  try {
    await pool.query('SELECT 1');
  } catch (e) {
    // Ignore keep-alive errors
  }
  next();
});

// Test connection and setup table
(async () => {
  let retries = 3;
  
  while (retries > 0) {
    try {
      console.log(`🔄 Connecting to database... (attempt ${4 - retries}/3)`);
      await pool.query('SELECT NOW()');
      console.log('✅ PostgreSQL Connected (Neon)');
      
      await pool.query(`
        CREATE TABLE IF NOT EXISTS users (
          id SERIAL PRIMARY KEY,
          username VARCHAR(50) NOT NULL,
          email VARCHAR(100) UNIQUE NOT NULL,
          password TEXT NOT NULL,
          role VARCHAR(50) DEFAULT 'Customer',
          company_id INTEGER,
          security_question1 VARCHAR(255) DEFAULT '',
          security_question2 VARCHAR(255) DEFAULT '',
          created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
          updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
          profile_image TEXT DEFAULT '',
          is_active BOOLEAN DEFAULT TRUE,
          email_verified BOOLEAN DEFAULT FALSE,
          last_login TIMESTAMP
        )
      `);
      console.log('✅ Users table ready');

      await pool.query(`
        CREATE TABLE IF NOT EXISTS companies (
          id SERIAL PRIMARY KEY,
          name VARCHAR(255) NOT NULL,
          code VARCHAR(50) UNIQUE NOT NULL,
          email VARCHAR(255),
          phone VARCHAR(50),
          is_active BOOLEAN DEFAULT true,
          created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
          updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
        )
      `);
      console.log('✅ Companies table ready');

      await pool.query(`
        INSERT INTO companies (name, code) 
        VALUES ('My Business', 'MYBIZ')
        ON CONFLICT (code) DO NOTHING
      `);
      
      const countResult = await pool.query('SELECT COUNT(*) FROM users');
      const userCount = parseInt(countResult.rows[0].count);
      console.log(`📊 Database has ${userCount} users`);
      
      break;
      
    } catch (error) {
      console.error(`❌ Connection attempt ${4 - retries} failed:`, error.message);
      retries--;
      
      if (retries > 0) {
        console.log('⏳ Retrying in 5 seconds...');
        await new Promise(resolve => setTimeout(resolve, 5000));
      } else {
        console.error('❌ All connection attempts failed');
      }
    }
  }
})();

// ========== MIDDLEWARE ==========
app.use(cors());
app.use(express.json());
app.use(express.static('public'));

// ========== ADMIN AUTH ==========
const ADMIN_PASSWORD = process.env.ADMIN_PASSWORD || 'admin123';

const verifyAdmin = (req, res, next) => {
  const authHeader = req.headers.authorization;
  if (!authHeader || !authHeader.startsWith('Bearer ')) {
    return res.status(401).json({ success: false, message: 'No token provided' });
  }
  
  const token = authHeader.split(' ')[1];
  if (token === ADMIN_PASSWORD) {
    next();
  } else {
    res.status(403).json({ success: false, message: 'Wrong admin password' });
  }
};

// ========== PASSWORD RESET WITH EMAIL CODE ==========
const resetCodes = {};
const generateResetCode = () => Math.floor(100000 + Math.random() * 900000).toString();

// SEND RESET CODE TO EMAIL
app.post('/api/auth/send-reset-code', async (req, res) => {
  try {
    const { email } = req.body;
    if (!email) return res.status(400).json({ status: 'error', message: 'Email required' });
    
    const result = await pool.query('SELECT id, username, email FROM users WHERE email = $1', [email]);
    if (result.rows.length === 0) {
      return res.json({ status: 'success', message: 'If your email exists, a reset code has been sent' });
    }
    
    const user = result.rows[0];
    const code = generateResetCode();
    resetCodes[email] = { code, userId: user.id, expiresAt: Date.now() + 10 * 60 * 1000 };
    
    await sendResetCodeEmail(email, code, user.username);
    console.log(`📧 Reset code sent to ${email}`);
    
    res.json({ status: 'success', message: 'Reset code sent to your email' });
  } catch (error) {
    console.error('Send code error:', error);
    res.status(500).json({ status: 'error', message: 'Failed to send code' });
  }
});

// VERIFY RESET CODE
app.post('/api/auth/verify-reset-code', async (req, res) => {
  try {
    const { email, code } = req.body;
    if (!email || !code) return res.status(400).json({ status: 'error', message: 'Email and code required' });
    
    const stored = resetCodes[email];
    if (!stored) return res.status(400).json({ status: 'error', message: 'No reset code found' });
    if (Date.now() > stored.expiresAt) { delete resetCodes[email]; return res.status(400).json({ status: 'error', message: 'Code expired' }); }
    if (stored.code !== code) return res.status(400).json({ status: 'error', message: 'Invalid code' });
    
    res.json({ status: 'success', message: 'Code verified' });
  } catch (error) {
    res.status(500).json({ status: 'error', message: error.message });
  }
});

// RESET PASSWORD WITH CODE
app.post('/api/auth/reset-password-code', async (req, res) => {
  try {
    const { email, code, newPassword } = req.body;
    if (!email || !code || !newPassword) return res.status(400).json({ status: 'error', message: 'All fields required' });
    
    const stored = resetCodes[email];
    if (!stored || stored.code !== code || Date.now() > stored.expiresAt) {
      return res.status(400).json({ status: 'error', message: 'Invalid or expired code' });
    }
    
    await pool.query('UPDATE users SET password = $1 WHERE id = $2', [newPassword, stored.userId]);
    delete resetCodes[email];
    
    res.json({ status: 'success', message: 'Password reset successfully!' });
  } catch (error) {
    res.status(500).json({ status: 'error', message: error.message });
  }
});

// ========== AUTH ROUTES ==========

// REGISTER
app.post('/api/auth/register', async (req, res) => {
  try {
    const { username, email, password, securityQuestions } = req.body;
    console.log(`👤 New registration: ${username}`);
    
    if (!username || !email || !password) {
      return res.status(400).json({ status: 'error', message: 'Username, email, and password are required' });
    }
    
    const existingEmail = await pool.query('SELECT id FROM users WHERE email = $1', [email]);
    if (existingEmail.rows.length > 0) {
      return res.status(400).json({ status: 'error', message: 'Email already registered' });
    }
    
    const existingUsername = await pool.query('SELECT id FROM users WHERE username = $1', [username]);
    if (existingUsername.rows.length > 0) {
      return res.status(400).json({ status: 'error', message: 'Username already taken' });
    }
    
    const result = await pool.query(
      `INSERT INTO users (username, email, password, role, security_question1, security_question2, email_verified) 
       VALUES ($1, $2, $3, 'Customer', $4, $5, false) 
       RETURNING id, username, email, role, company_id, is_active, created_at`,
      [username, email, password, securityQuestions?.question1 || '', securityQuestions?.question2 || '']
    );
    
    const newUser = result.rows[0];  // ✅ Variable is newUser
    
    // ✅ Use newUser
    const verifyCode = Math.floor(100000 + Math.random() * 900000).toString();
    resetCodes[email] = { code: verifyCode, userId: newUser.id, expiresAt: Date.now() + 30 * 60 * 1000, type: 'verify' };
    await sendVerificationEmail(email, verifyCode, username);
    console.log(`📧 Verification email sent to ${email}`);
    
    res.status(201).json({
      status: 'success',
      message: 'Registration successful! Check your email to verify.',
      data: {
        user: {
          id: newUser.id, _id: newUser.id, username: newUser.username,
          email: newUser.email, role: newUser.role, companyId: newUser.company_id,
          isActive: newUser.is_active, emailVerified: false
        },
        token: 'token_' + newUser.id
      }
    });
  } catch (error) {
    console.error('❌ Registration error:', error.message);
    res.status(500).json({ status: 'error', message: error.message });
  }
});

// LOGIN
app.post('/api/auth/login', async (req, res) => {
  try {
    const { username, email, password } = req.body;
    console.log(`🔑 Login: ${email || username}`);
    
    if (!password || (!email && !username)) {
      return res.status(400).json({ status: 'error', message: 'Email/username and password required' });
    }
    
    let result;
    if (email) {
      result = await pool.query(
        'SELECT id, username, email, password, role, email_verified, company_id, is_active FROM users WHERE email = $1', [email]
      );
    } else {
      result = await pool.query(
        'SELECT id, username, email, password, role, email_verified, company_id, is_active FROM users WHERE username = $1', [username]
      );
    }
    
    if (result.rows.length === 0) {
      return res.status(401).json({ status: 'error', message: 'Invalid credentials' });
    }
    
    const user = result.rows[0];
    
    if (!user.is_active) {
      return res.status(403).json({ status: 'error', message: 'Account is deactivated.' });
    }
    
    // ✅ BLOCK unverified users
    if (!user.email_verified) {
      return res.status(403).json({ 
        status: 'error', 
        message: 'Please verify your email first. Check your inbox for the verification link.' 
      });
    }
    
    if (password !== user.password) {
      return res.status(401).json({ status: 'error', message: 'Invalid credentials' });
    }
    
    await pool.query('UPDATE users SET last_login = CURRENT_TIMESTAMP WHERE id = $1', [user.id]);
    
    res.json({
      status: 'success',
      message: 'Login successful',
      data: {
        user: {
          id: user.id, _id: user.id, username: user.username,
          email: user.email, role: user.role, companyId: user.company_id,
          isActive: user.is_active, emailVerified: user.email_verified
        },
        token: 'token_' + user.id
      }
    });
  } catch (error) {
    console.error('❌ Login error:', error.message);
    res.status(500).json({ status: 'error', message: 'Login failed' });
  }
});
// RESEND VERIFICATION EMAIL
app.post('/api/auth/resend-verification', async (req, res) => {
  try {
    const { email } = req.body;
    if (!email) return res.status(400).json({ status: 'error', message: 'Email required' });
    
    const result = await pool.query('SELECT id, username, email_verified FROM users WHERE email = $1', [email]);
    if (result.rows.length === 0) {
      return res.json({ status: 'success', message: 'If email exists, verification sent' });
    }
    
    const user = result.rows[0];
    if (user.email_verified) {
      return res.json({ status: 'success', message: 'Email already verified' });
    }
    
    const code = Math.floor(100000 + Math.random() * 900000).toString();
    resetCodes[email] = { code, userId: user.id, expiresAt: Date.now() + 30 * 60 * 1000, type: 'verify' };
    await sendVerificationEmail(email, code, user.username);
    console.log(`📧 Verification email resent to ${email}`);
    
    res.json({ status: 'success', message: 'Verification email sent!' });
  } catch (error) {
    res.status(500).json({ status: 'error', message: error.message });
  }
});
// GET PROFILE
app.get('/api/auth/me', async (req, res) => {
  try {
    const userId = req.headers['user-id'] || req.query.userId;
    if (!userId) return res.status(400).json({ status: 'error', message: 'User ID required' });
    
    const result = await pool.query(
      'SELECT id, username, email, role, company_id, is_active, last_login, created_at FROM users WHERE id = $1', [userId]
    );
    
    if (result.rows.length === 0) return res.status(404).json({ status: 'error', message: 'User not found' });
    
    const user = result.rows[0];
    res.json({
      status: 'success',
      data: {
        user: {
          id: user.id, _id: user.id, username: user.username,
          email: user.email, role: user.role, companyId: user.company_id,
          isActive: user.is_active, lastLogin: user.last_login, createdAt: user.created_at
        }
      }
    });
  } catch (error) {
    res.status(500).json({ status: 'error', message: error.message });
  }
});

// LOGOUT
app.post('/api/auth/logout', (req, res) => {
  res.json({ status: 'success', message: 'Logged out successfully' });
});

// CREATE STAFF (Admin & Manager)

// CREATE STAFF (Admin & Manager)
app.post('/api/auth/create-staff', async (req, res) => {
  try {
    const { username, email, password, securityQuestions } = req.body;
    const creatorId = req.headers['user-id'];
    console.log(`👤 Creating staff: ${username} by user ID: ${creatorId}`);
    
    const existing = await pool.query('SELECT id FROM users WHERE username = $1 OR email = $2', [username, email]);
    if (existing.rows.length > 0) {
      return res.status(400).json({ status: 'error', message: 'Username or email already exists' });
    }
    
    // FIX: Parse creatorId to integer
    let companyId = null;
    if (creatorId) {
      const creator = await pool.query(
        'SELECT company_id, role FROM users WHERE id = $1', 
        [parseInt(creatorId)]  // Convert string to integer!
      );
      if (creator.rows.length > 0) {
        companyId = creator.rows[0].company_id;
        console.log(`🏢 Creator company_id: ${companyId}`);
      }
    }
    
    const result = await pool.query(
      `INSERT INTO users (username, email, password, role, company_id, security_question1, security_question2) 
       VALUES ($1, $2, $3, 'Staff', $4, $5, $6) 
       RETURNING id, username, email, role, company_id, is_active, created_at`,
      [username, email, password, companyId, securityQuestions?.question1 || '', securityQuestions?.question2 || '']
    );
    
    console.log(`✅ Staff created: ${username} with company_id: ${result.rows[0].company_id}`);
    
    res.status(201).json({
      status: 'success',
      message: 'Staff created successfully',
      data: {
        user: {
          id: result.rows[0].id, _id: result.rows[0].id,
          username: result.rows[0].username, email: result.rows[0].email,
          role: result.rows[0].role, companyId: result.rows[0].company_id,
          isActive: result.rows[0].is_active
        }
      }
    });
  } catch (error) {
    console.error('❌ Create staff error:', error.message);
    res.status(500).json({ status: 'error', message: error.message });
  }
});
// BLOCK USER
app.post('/api/auth/block-user/:id', async (req, res) => {
  try {
    const userId = req.params.id;
    const userResult = await pool.query('SELECT id, username, role FROM users WHERE id = $1', [userId]);
    if (userResult.rowCount === 0) return res.status(404).json({ status: 'error', message: 'User not found' });
    
    const user = userResult.rows[0];
    if (user.role === 'Administrator') return res.status(403).json({ status: 'error', message: 'Cannot block Administrator' });
    
    const result = await pool.query(
      'UPDATE users SET is_active = false, updated_at = CURRENT_TIMESTAMP WHERE id = $1 RETURNING id, username, email, role, is_active', [userId]
    );
    
    res.json({ status: 'success', message: `${result.rows[0].username} blocked`, data: { user: { id: result.rows[0].id, username: result.rows[0].username, role: result.rows[0].role, isActive: false } } });
  } catch (error) {
    res.status(500).json({ status: 'error', message: error.message });
  }
});

// UNBLOCK USER
app.post('/api/auth/unblock-user/:id', async (req, res) => {
  try {
    const userId = req.params.id;
    const userResult = await pool.query('SELECT id FROM users WHERE id = $1', [userId]);
    if (userResult.rowCount === 0) return res.status(404).json({ status: 'error', message: 'User not found' });
    
    const result = await pool.query(
      'UPDATE users SET is_active = true, updated_at = CURRENT_TIMESTAMP WHERE id = $1 RETURNING id, username, email, role, is_active', [userId]
    );
    
    res.json({ status: 'success', message: `${result.rows[0].username} unblocked`, data: { user: { id: result.rows[0].id, username: result.rows[0].username, role: result.rows[0].role, isActive: true } } });
  } catch (error) {
    res.status(500).json({ status: 'error', message: error.message });
  }
});

// DELETE USER (Admin)
app.delete('/api/auth/users/:id', verifyAdmin, async (req, res) => {
  try {
    const userId = req.params.id;
    const userResult = await pool.query('SELECT id, username, role FROM users WHERE id = $1', [userId]);
    if (userResult.rowCount === 0) return res.status(404).json({ status: 'error', message: 'User not found' });
    
    const user = userResult.rows[0];
    if (user.role === 'Administrator') return res.status(403).json({ status: 'error', message: 'Cannot delete Administrator' });
    
    await pool.query('DELETE FROM users WHERE id = $1', [userId]);
    
    res.json({ status: 'success', message: `${user.username} deleted permanently`, data: { deletedUser: { id: user.id, username: user.username, role: user.role } } });
  } catch (error) {
    res.status(500).json({ status: 'error', message: error.message });
  }
});

// GET USERS
app.get('/api/users', async (req, res) => {
  try {
    const { role, search } = req.query;
    const requesterId = req.headers['user-id'];
    let query = 'SELECT id, username, email, role, company_id, is_active, created_at, last_login FROM users WHERE 1=1';
    const params = [];
    let p = 1;
    
    if (role) { query += ` AND role = $${p}`; params.push(role); p++; }
    if (search) { query += ` AND (username ILIKE $${p} OR email ILIKE $${p})`; params.push(`%${search}%`); p++; }
        if (requesterId) {
      const requester = await pool.query('SELECT role, company_id FROM users WHERE id = $1', [parseInt(requesterId)]);
      if (requester.rows.length > 0 && requester.rows[0].role === 'Manager') {
        const managerCompanyId = requester.rows[0].company_id;
        if (managerCompanyId) {
          query += ` AND company_id = $${p}`;
          params.push(managerCompanyId);
          p++;
          console.log(`🔒 Filtering by company_id: ${managerCompanyId}`);
        }
      }
      // Admin sees all users
    }

    query += ' ORDER BY created_at DESC';
    const result = await pool.query(query, params);
    
    res.json({
      status: 'success',
      data: { users: result.rows.map(u => ({ _id: u.id, id: u.id, username: u.username, email: u.email, role: u.role, companyId: u.company_id, isActive: u.is_active, createdAt: u.created_at, lastLogin: u.last_login })) }
    });
  } catch (error) {
    res.status(500).json({ status: 'error', message: error.message });
  }
});

// UPDATE USER
app.put('/api/users/:id', verifyAdmin, async (req, res) => {
  try {
    const { id } = req.params;
    const { role, company_id } = req.body;
    const result = await pool.query(
      'UPDATE users SET role = COALESCE($1, role), company_id = $2, updated_at = CURRENT_TIMESTAMP WHERE id = $3 RETURNING id, username, email, role, company_id, is_active',
      [role, company_id, id]
    );
    if (result.rowCount === 0) return res.status(404).json({ status: 'error', message: 'User not found' });
    res.json({ status: 'success', message: 'User updated', data: { user: result.rows[0] } });
  } catch (error) {
    res.status(500).json({ status: 'error', message: error.message });
  }
});

// ========== ADMIN ROUTES ==========

app.get('/api/admin/users', verifyAdmin, async (req, res) => {
  try {
    const result = await pool.query('SELECT id, username, email, role, company_id, created_at, last_login, is_active FROM users ORDER BY created_at DESC');
    const users = result.rows.map(u => ({ _id: u.id, id: u.id, name: u.username, username: u.username, email: u.email, role: u.role, companyId: u.company_id, createdAt: u.created_at, lastLogin: u.last_login, isActive: u.is_active, isAdmin: u.role === 'Administrator' }));
    res.json({ success: true, count: users.length, users, status: 'success', data: { users } });
  } catch (error) {
    res.status(500).json({ success: false, message: error.message });
  }
});

app.get('/api/admin/stats', verifyAdmin, async (req, res) => {
  try {
    const total = await pool.query('SELECT COUNT(*) FROM users');
    const today = new Date(); today.setHours(0,0,0,0);
    const newToday = await pool.query('SELECT COUNT(*) FROM users WHERE created_at >= $1', [today]);
    const active = await pool.query('SELECT COUNT(*) FROM users WHERE is_active = true');
    res.json({ success: true, totalUsers: parseInt(total.rows[0].count), newToday: parseInt(newToday.rows[0].count), activeUsers: parseInt(active.rows[0].count) });
  } catch (error) {
    res.status(500).json({ success: false, message: error.message });
  }
});

app.delete('/api/admin/users/:id', verifyAdmin, async (req, res) => {
  try {
    const result = await pool.query('DELETE FROM users WHERE id = $1 RETURNING username, email, role', [req.params.id]);
    if (result.rowCount === 0) return res.status(404).json({ success: false, message: 'User not found' });
    res.json({ success: true, message: 'User deleted', deletedUser: result.rows[0] });
  } catch (error) {
    res.status(500).json({ success: false, message: error.message });
  }
});

// ========== OTHER ROUTES ==========

// GET DRINKS FROM DATABASE
app.get('/api/drinks', async (req, res) => {
  try {
    const result = await pool.query(
      'SELECT * FROM drinks WHERE is_active = true ORDER BY name ASC'
    );
    
    res.json({
      success: true,
      count: result.rows.length,
      drinks: result.rows
    });
  } catch (error) {
    // If drinks table doesn't exist yet, return empty array
    res.json({ 
      success: true, 
      count: 0, 
      drinks: [],
      message: 'No drinks table yet. Create one or use the app to add drinks.'
    });
  }
});
app.get('/api/test', (req, res) => {
  res.json({ success: true, message: 'DrinkQuick API v3.0', working: true, database: 'Neon PostgreSQL', email: 'Enabled' });
});

app.get('/api/ping', (req, res) => {
  res.json({ success: true, message: 'pong' });
});

app.get('/', (req, res) => {
  res.json({ success: true, message: 'DrinkQuick API 🍹', version: '2.0', status: '🟢 ONLINE', database: 'Neon PostgreSQL' });
});

app.get('/health', async (req, res) => {
  try {
    await pool.query('SELECT NOW()');
    const count = await pool.query('SELECT COUNT(*) FROM users');
    res.json({ success: true, status: '✅ ONLINE', database: '✅ CONNECTED', users: parseInt(count.rows[0].count) });
  } catch (e) {
    res.json({ success: true, status: '⚠️ ONLINE', database: '❌ DISCONNECTED', error: e.message });
  }
});

app.get('/debug-db', async (req, res) => {
  try {
    const count = await pool.query('SELECT COUNT(*) FROM users');
    const cols = await pool.query("SELECT column_name, data_type FROM information_schema.columns WHERE table_name = 'users' AND table_schema = 'public' ORDER BY ordinal_position");
    res.json({ success: true, users: { total: parseInt(count.rows[0].count) }, columns: cols.rows });
  } catch (e) {
    res.json({ success: false, error: e.message });
  }
});

app.get('/admin', (req, res) => {
  res.sendFile(path.join(__dirname, 'public', 'admin.html'));
});
// CONFIRM EMAIL (clicked from email link)
// CONFIRM EMAIL (clicked from email link)
app.get('/api/auth/confirm-email', async (req, res) => {
  try {
    const { email, code } = req.query;
    
    if (!email || !code) {
      return res.send(`<!DOCTYPE html><html><head><meta charset="UTF-8"><meta name="viewport" content="width=device-width, initial-scale=1.0"><style>*{margin:0;padding:0;box-sizing:border-box;}body{font-family:Arial,sans-serif;min-height:100vh;display:flex;align-items:center;justify-content:center;background:linear-gradient(135deg,#667EEA,#764BA2);padding:20px;}.card{background:white;padding:40px;border-radius:20px;text-align:center;max-width:400px;box-shadow:0 10px 40px rgba(0,0,0,0.2);}.icon{font-size:60px;margin-bottom:15px;}h1{color:#e74c3c;font-size:22px;margin-bottom:10px;}p{color:#666;font-size:14px;}</style></head><body><div class="card"><div class="icon">❌</div><h1>Invalid Link</h1><p>The verification link is invalid or incomplete.</p></div></body></html>`);
    }
    
    const stored = resetCodes[email];
    if (!stored || stored.type !== 'verify') {
      return res.send(`<!DOCTYPE html><html><head><meta charset="UTF-8"><meta name="viewport" content="width=device-width, initial-scale=1.0"><style>*{margin:0;padding:0;box-sizing:border-box;}body{font-family:Arial,sans-serif;min-height:100vh;display:flex;align-items:center;justify-content:center;background:linear-gradient(135deg,#667EEA,#764BA2);padding:20px;}.card{background:white;padding:40px;border-radius:20px;text-align:center;max-width:400px;box-shadow:0 10px 40px rgba(0,0,0,0.2);}.icon{font-size:60px;margin-bottom:15px;}h1{color:#e74c3c;font-size:22px;margin-bottom:10px;}p{color:#666;font-size:14px;}</style></head><body><div class="card"><div class="icon">❌</div><h1>Not Found</h1><p>No verification found. Please register again.</p></div></body></html>`);
    }
    
    if (Date.now() > stored.expiresAt) {
      delete resetCodes[email];
      return res.send(`<!DOCTYPE html><html><head><meta charset="UTF-8"><meta name="viewport" content="width=device-width, initial-scale=1.0"><style>*{margin:0;padding:0;box-sizing:border-box;}body{font-family:Arial,sans-serif;min-height:100vh;display:flex;align-items:center;justify-content:center;background:linear-gradient(135deg,#667EEA,#764BA2);padding:20px;}.card{background:white;padding:40px;border-radius:20px;text-align:center;max-width:400px;box-shadow:0 10px 40px rgba(0,0,0,0.2);}.icon{font-size:60px;margin-bottom:15px;}h1{color:#ff9800;font-size:22px;margin-bottom:10px;}p{color:#666;font-size:14px;}</style></head><body><div class="card"><div class="icon">⏰</div><h1>Link Expired</h1><p>This verification link has expired. Please register again.</p></div></body></html>`);
    }
    
    if (stored.code !== code) {
      return res.send(`<!DOCTYPE html><html><head><meta charset="UTF-8"><meta name="viewport" content="width=device-width, initial-scale=1.0"><style>*{margin:0;padding:0;box-sizing:border-box;}body{font-family:Arial,sans-serif;min-height:100vh;display:flex;align-items:center;justify-content:center;background:linear-gradient(135deg,#667EEA,#764BA2);padding:20px;}.card{background:white;padding:40px;border-radius:20px;text-align:center;max-width:400px;box-shadow:0 10px 40px rgba(0,0,0,0.2);}.icon{font-size:60px;margin-bottom:15px;}h1{color:#e74c3c;font-size:22px;margin-bottom:10px;}p{color:#666;font-size:14px;}</style></head><body><div class="card"><div class="icon">❌</div><h1>Invalid Code</h1><p>The verification code is incorrect.</p></div></body></html>`);
    }
    
    await pool.query('UPDATE users SET email_verified = true WHERE id = $1', [stored.userId]);
    delete resetCodes[email];
    
    // ✅ Beautiful success page
    res.send(`
      <!DOCTYPE html>
      <html>
      <head>
        <meta charset="UTF-8">
        <meta name="viewport" content="width=device-width, initial-scale=1.0">
        <title>Email Verified</title>
        <style>
          * { margin: 0; padding: 0; box-sizing: border-box; }
          body { 
            font-family: Arial, sans-serif; 
            min-height: 100vh; 
            display: flex; 
            align-items: center; 
            justify-content: center; 
            background: linear-gradient(135deg, #667EEA, #764BA2);
            padding: 20px;
          }
          .card {
            background: white;
            padding: 40px;
            border-radius: 20px;
            text-align: center;
            max-width: 400px;
            box-shadow: 0 10px 40px rgba(0,0,0,0.2);
          }
          .icon { font-size: 60px; margin-bottom: 15px; }
          h1 { color: #38b000; font-size: 24px; margin-bottom: 10px; }
          p { color: #666; font-size: 14px; margin-bottom: 15px; }
          .btn {
            display: inline-block;
            background: #667EEA;
            color: white;
            padding: 12px 30px;
            border-radius: 10px;
            text-decoration: none;
            font-weight: bold;
            margin-top: 10px;
          }
        </style>
      </head>
      <body>
        <div class="card">
          <div class="icon">✅</div>
          <h1>Email Verified!</h1>
          <p>Your email <strong>${email}</strong> has been verified successfully.</p>
          <p>You can now return to the app and login to your account.</p>
        </div>
        <script>
          setTimeout(function() {
            window.close();
          }, 3000);
        </script>
      </body>
      </html>
    `);
    
  } catch (error) {
    res.send(`<!DOCTYPE html><html><head><meta charset="UTF-8"><meta name="viewport" content="width=device-width, initial-scale=1.0"><style>*{margin:0;padding:0;box-sizing:border-box;}body{font-family:Arial,sans-serif;min-height:100vh;display:flex;align-items:center;justify-content:center;background:linear-gradient(135deg,#667EEA,#764BA2);padding:20px;}.card{background:white;padding:40px;border-radius:20px;text-align:center;max-width:400px;box-shadow:0 10px 40px rgba(0,0,0,0.2);}.icon{font-size:60px;margin-bottom:15px;}h1{color:#e74c3c;font-size:22px;margin-bottom:10px;}p{color:#666;font-size:14px;}</style></head><body><div class="card"><div class="icon">❌</div><h1>Server Error</h1><p>Please try again later.</p></div></body></html>`);
  }
});
// ========== 404 ==========
app.use((req, res) => {
  res.status(404).json({ success: false, message: 'Route not found' });
});

// ========== START ==========
const PORT = process.env.PORT || 3000;
app.listen(PORT, '0.0.0.0', () => {
  console.log(`\n🚀 DRINKQUICK SERVER v2.0 🚀`);
  console.log(`📍 Port: ${PORT}`);
  console.log('🗄️  Database: Neon PostgreSQL');
  console.log('📧 Email: Password Reset Codes Enabled\n');
});
