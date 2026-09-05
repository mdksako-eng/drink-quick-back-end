const express = require('express');
const cors = require('cors');
const path = require('path');
const { Pool } = require('pg');
const bcrypt = require('bcryptjs');
require('dotenv').config();

const app = express();

// ========== EMAIL SERVICE ==========
const { sendResetCodeEmail, sendWelcomeEmail, sendVerificationEmail, sendJoinRequestEmail } = require('./utils/email.service');

// ========== SESSION AUTH (DB-backed) ==========
const { generateSessionToken, getSessionUser, requireSession } = require('./middleware/sessionAuth');

// ========== PASSWORD HELPERS ===========
// Passwords are stored as bcrypt hashes ($2a$ / $2b$ / $2y$).
// Legacy rows with plaintext passwords are upgraded automatically on next successful login.
const isBcryptHash = (stored) => typeof stored === 'string' && stored.startsWith('$2');

// ========== RATE LIMITING (in-memory) ==========
const rateLimitBuckets = new Map();
const RATE_MAX_ATTEMPTS = 10;
const RATE_WINDOW_MS = 15 * 60 * 1000;

function checkRateLimit(key) {
  const now = Date.now();
  const entry = rateLimitBuckets.get(key);
  if (!entry || now > entry.resetAt) {
    rateLimitBuckets.set(key, { count: 1, resetAt: now + RATE_WINDOW_MS });
    return true;
  }
  entry.count += 1;
  return entry.count <= RATE_MAX_ATTEMPTS;
}

// ========== POSTGRESQL SETUP ==========
console.log('🔌 Connecting to PostgreSQL (Supabase)...');

const databaseUrl = process.env.DATABASE_URL;
console.log('🔍 DATABASE_URL is set:', databaseUrl ? 'YES' : 'NO');

const pool = new Pool({
  connectionString: databaseUrl,
  ssl: { 
    rejectUnauthorized: false 
  },
  connectionTimeoutMillis: 30000,
  idleTimeoutMillis: 60000,
  max: 10,
  keepAlive: true,
  keepAliveInitialDelayMillis: 10000,
  family: 4
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

// Test connection and setup tables
(async () => {
  let retries = 3;
  
  while (retries > 0) {
    try {
      console.log(`🔄 Connecting to Supabase... (attempt ${4 - retries}/3)`);
      await pool.query('SELECT NOW()');
      console.log('✅ PostgreSQL Connected (Supabase)');
      
      // Check if users table exists
      const tableCheck = await pool.query(`
        SELECT EXISTS (
          SELECT FROM information_schema.tables 
          WHERE table_schema = 'public' AND table_name = 'users'
        );
      `);
      
      const usersExist = tableCheck.rows[0].exists;
      
      if (!usersExist) {
        console.log('📦 Creating users table...');
        await pool.query(`
          CREATE TABLE IF NOT EXISTS users (
            id SERIAL PRIMARY KEY,
            username VARCHAR(50) NOT NULL,
            email VARCHAR(100) UNIQUE NOT NULL,
            password TEXT NOT NULL,
            phone VARCHAR(20),
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
        console.log('✅ Users table created');
      } else {
        console.log('✅ Users table already exists');
      }

      // 🔐 OWNERSHIP MIGRATION — add companies.owner_id and backfill the
      // earliest-created Manager of each company as its founder/owner.
      try {
        await pool.query(`
          ALTER TABLE companies ADD COLUMN IF NOT EXISTS owner_id INTEGER
        `);
        await pool.query(`
          ALTER TABLE companies ADD COLUMN IF NOT EXISTS address TEXT
        `);
        await pool.query(`
          UPDATE companies c
          SET owner_id = sub.first_manager
          FROM (
            SELECT company_id, MIN(id) AS first_manager
            FROM users
            WHERE role IN ('Manager', 'Administrator') AND company_id IS NOT NULL
            GROUP BY company_id
          ) sub
          WHERE c.id = sub.company_id AND c.owner_id IS NULL
        `);
        console.log('✅ Company ownership column ensured (owner_id backfilled)');
      } catch (ownErr) {
        console.log('⚠️ Ownership migration warning:', ownErr.message);
      }

      // Check companies table
      const companiesCheck = await pool.query(`
        SELECT EXISTS (
          SELECT FROM information_schema.tables 
          WHERE table_schema = 'public' AND table_name = 'companies'
        );
      `);
      
      const companiesExist = companiesCheck.rows[0].exists;
      
      if (!companiesExist) {
        console.log('📦 Creating companies table...');
        await pool.query(`
          CREATE TABLE IF NOT EXISTS companies (
            id SERIAL PRIMARY KEY,
            name VARCHAR(255) NOT NULL,
            code VARCHAR(50) UNIQUE NOT NULL,
            invite_code VARCHAR(50) UNIQUE,
            email VARCHAR(255),
            phone VARCHAR(50),
            is_active BOOLEAN DEFAULT true,
            created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
            updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
          )
        `);
        console.log('✅ Companies table created');
      } else {
        console.log('✅ Companies table already exists');
      }

      // Check user_sessions table
      const sessionsCheck = await pool.query(`
        SELECT EXISTS (
          SELECT FROM information_schema.tables 
          WHERE table_schema = 'public' AND table_name = 'user_sessions'
        );
      `);
      
      const sessionsExist = sessionsCheck.rows[0].exists;
      
      if (!sessionsExist) {
        console.log('📦 Creating user_sessions table...');
        await pool.query(`
          CREATE TABLE IF NOT EXISTS user_sessions (
            id SERIAL PRIMARY KEY,
            user_id INTEGER NOT NULL REFERENCES users(id) ON DELETE CASCADE,
            session_token TEXT NOT NULL UNIQUE,
            device_id TEXT,
            device_name TEXT,
            is_active BOOLEAN DEFAULT true,
            created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
            last_activity_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
            expires_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP + INTERVAL '8 hours',
            terminated_at TIMESTAMP
          )
        `);
        console.log('✅ user_sessions table created');
      } else {
        console.log('✅ user_sessions table already exists');
      }

      // Check login_requests table
      const requestsCheck = await pool.query(`
        SELECT EXISTS (
          SELECT FROM information_schema.tables 
          WHERE table_schema = 'public' AND table_name = 'login_requests'
        );
      `);
      
      const requestsExist = requestsCheck.rows[0].exists;
      
      if (!requestsExist) {
        console.log('📦 Creating login_requests table...');
        await pool.query(`
          CREATE TABLE IF NOT EXISTS login_requests (
            id SERIAL PRIMARY KEY,
            user_id INTEGER NOT NULL REFERENCES users(id) ON DELETE CASCADE,
            request_token TEXT NOT NULL UNIQUE,
            device_id TEXT,
            device_name TEXT,
            status VARCHAR(20) DEFAULT 'pending',
            existing_session_token TEXT,
            new_session_token TEXT,
            approved_by INTEGER,
            request_time TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
            expires_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP + INTERVAL '15 minutes',
            approved_at TIMESTAMP,
            terminated_at TIMESTAMP
          )
        `);
        console.log('✅ login_requests table created');
      } else {
        console.log('✅ login_requests table already exists');
      }

      // Check company_join_requests table
      const joinReqCheck = await pool.query(`
        SELECT EXISTS (
          SELECT FROM information_schema.tables 
          WHERE table_schema = 'public' AND table_name = 'company_join_requests'
        );
      `);
      const joinReqExist = joinReqCheck.rows[0].exists;
      if (!joinReqExist) {
        console.log('📦 Creating company_join_requests table...');
        await pool.query(`
          CREATE TABLE IF NOT EXISTS company_join_requests (
            id SERIAL PRIMARY KEY,
            company_id INTEGER NOT NULL,
            user_id INTEGER NOT NULL,
            requested_role VARCHAR(50) DEFAULT 'Staff',
            code VARCHAR(10) NOT NULL,
            status VARCHAR(20) DEFAULT 'pending',
            attempts INTEGER DEFAULT 0,
            approved_by INTEGER,
            expires_at TIMESTAMP,
            created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
            resolved_at TIMESTAMP
          )
        `);
        console.log('✅ company_join_requests table created');
      } else {
        console.log('✅ company_join_requests table already exists');
      }

      // 🔐 Lock down company_join_requests: RLS on + revoke client roles.
      // The backend connects as the table owner (postgres) and BYPASSES RLS,
      // so /api/auth flows keep working, while the anon key shipped in the
      // Flutter app can no longer read join requests or verification codes.
      try {
        await pool.query(`ALTER TABLE company_join_requests ENABLE ROW LEVEL SECURITY`);
        await pool.query(`REVOKE ALL ON company_join_requests FROM anon, authenticated`);
        console.log('✅ RLS enabled on company_join_requests (anon access revoked)');
      } catch (rlsErr) {
        console.log('⚠️ RLS lockdown warning for company_join_requests:', rlsErr.message);
      }

      // Check approval_logs table
      const logsCheck = await pool.query(`
        SELECT EXISTS (
          SELECT FROM information_schema.tables 
          WHERE table_schema = 'public' AND table_name = 'approval_logs'
        );
      `);
      
      const logsExist = logsCheck.rows[0].exists;
      
      if (!logsExist) {
        console.log('📦 Creating approval_logs table...');
        await pool.query(`
          CREATE TABLE IF NOT EXISTS approval_logs (
            id SERIAL PRIMARY KEY,
            request_token TEXT,
            manager_id INTEGER REFERENCES users(id),
            staff_id INTEGER REFERENCES users(id),
            staff_name VARCHAR(100),
            device_name VARCHAR(255),
            action VARCHAR(20),
            details TEXT,
            timestamp TIMESTAMP DEFAULT CURRENT_TIMESTAMP
          )
        `);
        console.log('✅ approval_logs table created');
      } else {
        console.log('✅ approval_logs table already exists');
      }
      
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
app.use(express.static(path.join(__dirname, 'public')));
// ✅ Database connection middleware - MUST BE BEFORE ROUTES
app.use(async (req, res, next) => {
  try {
    // Test database connection
    await pool.query('SELECT 1');
    req.db = pool;  // ✅ This makes `req.db` available
    next();
  } catch (error) {
    console.error('❌ Database connection error:', error.message);
    // Still allow the request to continue, but set req.db
    req.db = pool;
    next();
  }
});
// ========== ADMIN AUTH ==========
const ADMIN_PASSWORD = process.env.ADMIN_PASSWORD || 'admin123';
if (!process.env.ADMIN_PASSWORD) {
  console.error('⚠️  WARNING: ADMIN_PASSWORD env var is NOT set. Falling back to the default "admin123" — this is INSECURE. Set ADMIN_PASSWORD in the environment immediately.');
}

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

    // ⏱️ Rate limit reset-code requests per email
    if (!checkRateLimit(`reset:${email}`)) {
      return res.status(429).json({ status: 'error', message: 'Too many reset requests. Try again in 15 minutes.' });
    }
    
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
    
    await pool.query('UPDATE users SET password = $1 WHERE id = $2', [await bcrypt.hash(newPassword, 10), stored.userId]);
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
    const { username, email, password, phone, securityQuestions, registerAsManager, companyId, companyName, companyCode, companyAddress } = req.body;
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
    
    let finalCompanyId = null;
    let userRole = 'Customer';
    let createdNewCompany = false;
    // 🔐 Pending join-request state (invite-code signups require owner approval)
    let pendingJoinCompanyId = null;
    let pendingJoinRole = null;
    let joinTargetCompany = null;
    
    if (registerAsManager) {
      if (companyId) {
        // Joining existing company — REQUIRES OWNER VERIFICATION.
        // The account is created unlinked (no company, Customer role) and a
        // 6-digit code is emailed to the company owner. The owner approves in
        // the app; only then does the user get their role/company. If the
        // owner rejects (or the request expires), the account is DELETED.
        const companyCheck = await pool.query('SELECT id, name, owner_id, email, phone FROM companies WHERE id = $1 AND is_active = true', [companyId]);
        if (companyCheck.rows.length === 0) {
          return res.status(404).json({ status: 'error', message: 'Company not found' });
        }
        const company = companyCheck.rows[0];
        finalCompanyId = null; // held until owner approval
        pendingJoinCompanyId = companyId;
        pendingJoinRole = 'Manager';
        joinTargetCompany = company;
        // Keep company contact details fresh
        await pool.query(
          'UPDATE companies SET email = COALESCE(email, $1), phone = COALESCE(phone, $2) WHERE id = $3',
          [email, phone || null, companyId]
        );
      } else if (companyName && companyCode) {
        // Creating new company — this user becomes the company OWNER
        userRole = 'Manager';
        const companyResult = await pool.query(
          `INSERT INTO companies (name, code, invite_code, email, phone, address) 
           VALUES ($1, $2, $2, $3, $4, $5) 
           ON CONFLICT (code) DO NOTHING
           RETURNING id`,
          [companyName, companyCode.toUpperCase(), email, phone || null, (companyAddress || '').trim() || null]
        );
        if (companyResult.rows.length > 0) {
          finalCompanyId = companyResult.rows[0].id;
          createdNewCompany = true;
        }
      }
    }
    
    // 🔒 Hash the password before storing — never persist plaintext
    const hashedPassword = await bcrypt.hash(password, 10);

    const result = await pool.query(
      `INSERT INTO users (username, email, password, phone, role, company_id, security_question1, security_question2, email_verified) 
       VALUES ($1, $2, $3, $4, $5, $6, $7, $8, false) 
       RETURNING id, username, email, phone, role, company_id, is_active, created_at`,
      [username, email, hashedPassword, phone || null, userRole, finalCompanyId, 
       securityQuestions?.question1 || '', securityQuestions?.question2 || '']
    );
    
    const newUser = result.rows[0];
    
    // 🔐 If this registration created a new company, mark the user as its OWNER
    if (createdNewCompany && finalCompanyId) {
      try {
        await pool.query('UPDATE companies SET owner_id = $1 WHERE id = $2', [newUser.id, finalCompanyId]);
      } catch (ownErr) {
        console.log('⚠️ Could not set company owner:', ownErr.message);
      }
    }

    // 🔐 OWNER-APPROVED JOIN: invite-code signup → pending request + code to owner
    let joinRequestId = null;
    if (pendingJoinCompanyId && joinTargetCompany) {
      const joinCode = Math.floor(100000 + Math.random() * 900000).toString();
      const joinInsert = await pool.query(
        `INSERT INTO company_join_requests (company_id, user_id, requested_role, code, status, expires_at)
         VALUES ($1, $2, $3, $4, 'pending', NOW() + INTERVAL '15 minutes') RETURNING id`,
        [pendingJoinCompanyId, newUser.id, pendingJoinRole, joinCode]
      );
      joinRequestId = joinInsert.rows[0].id;
      // Email the verification code to the company OWNER
      try {
        let ownerEmail = joinTargetCompany.email;
        if (joinTargetCompany.owner_id) {
          const ownerRow = await pool.query('SELECT email, username FROM users WHERE id = $1', [joinTargetCompany.owner_id]);
          if (ownerRow.rows.length > 0) ownerEmail = ownerRow.rows[0].email;
        }
        if (ownerEmail) {
          await sendJoinRequestEmail(ownerEmail, joinTargetCompany.name, username, joinTargetCompany.name, joinCode, pendingJoinRole);
          console.log(`📧 Join verification code sent to company owner (${ownerEmail})`);
        } else {
          console.log('⚠️ Company has no owner email — join cannot be verified');
        }
      } catch (e) {
        console.log('⚠️ Join request email failed:', e.message);
      }
    }
    
    // Send verification email
    const verifyCode = Math.floor(100000 + Math.random() * 900000).toString();
    resetCodes[email] = { code: verifyCode, userId: newUser.id, expiresAt: Date.now() + 30 * 60 * 1000, type: 'verify' };
    
    try {
      await sendVerificationEmail(email, verifyCode, username);
      console.log(`📧 Verification email sent to ${email}`);
    } catch (e) {
      console.log('⚠️ Verification email failed:', e.message);
    }
    
    const responseMessage = joinRequestId
      ? 'Request sent! The company owner must verify you with the code emailed to them before your account is activated.'
      : (registerAsManager ? 'Business account created! Check email to verify.' : 'Account created! Check email to verify.');

    res.status(201).json({
      status: 'success',
      message: responseMessage,
      data: {
        pendingJoinApproval: joinRequestId != null,
        joinRequestId: joinRequestId,
        user: {
          id: newUser.id, _id: newUser.id, username: newUser.username,
          email: newUser.email, phone: newUser.phone, role: newUser.role,
          companyId: newUser.company_id, isActive: newUser.is_active, emailVerified: false,
          isOwner: createdNewCompany
        },
        // ⚠️ Placeholder token — the real session is created on first login.
        token: generateSessionToken()
      }
    });
  } catch (error) {
    console.error('❌ Registration error:', error.message);
    res.status(500).json({ status: 'error', message: error.message });
  }
});

// ✅ LOGIN - Updated with Staff Approval System
app.post('/api/auth/login', async (req, res) => {
  try {
    const { username, email, password, deviceId, deviceName } = req.body;
    console.log(`🔑 Login: ${email || username}`);
    console.log(`📱 Device ID: ${deviceId}`);
    console.log(`📱 Device Name: ${deviceName}`);
    
    if (!password || (!email && !username)) {
      return res.status(400).json({ status: 'error', message: 'Email/username and password required' });
    }

    // ⏱️ Simple rate limit to slow down brute-force attempts
    if (!checkRateLimit(`login:${email || username}`)) {
      return res.status(429).json({ status: 'error', message: 'Too many login attempts. Try again in 15 minutes.' });
    }
    
    let result;
    if (email) {
      result = await pool.query(
        'SELECT id, username, email, password, role, email_verified, company_id, is_active FROM users WHERE email = $1',
        [email]
      );
    } else {
      result = await pool.query(
        'SELECT id, username, email, password, role, email_verified, company_id, is_active FROM users WHERE username = $1',
        [username]
      );
    }
    
    if (result.rows.length === 0) {
      return res.status(401).json({ status: 'error', message: 'Invalid credentials' });
    }
    
    const user = result.rows[0];
    
    if (!user.is_active) {
      return res.status(403).json({ status: 'error', message: 'Account is deactivated.' });
    }
    
    if (!user.email_verified) {
      return res.status(403).json({ 
        status: 'error', 
        message: 'Please verify your email first.',
        code: 'EMAIL_NOT_VERIFIED'
      });
    }
    
    // 🔒 BLOCK LOGIN for pending join-request users (company_id is NULL until owner approves)
    if (!user.company_id) {
      const pendingJoin = await pool.query(
        `SELECT j.id, j.company_id, j.status, c.name AS company_name
         FROM company_join_requests j
         JOIN companies c ON c.id = j.company_id
         WHERE j.user_id = $1 AND j.status = 'pending' AND j.expires_at > NOW()
         LIMIT 1`,
        [user.id]
      );
      if (pendingJoin.rows.length > 0) {
        return res.status(403).json({
          status: 'error',
          message: `Your join request for "${pendingJoin.rows[0].company_name}" is awaiting owner verification. You will be able to log in once approved.`,
          code: 'JOIN_PENDING_APPROVAL'
        });
      }
    }
    
    // 🔒 Verify password — supports bcrypt hashes and legacy plaintext (migrates on success)
    let passwordValid = false;
    if (isBcryptHash(user.password)) {
      passwordValid = await bcrypt.compare(password, user.password);
    } else {
      passwordValid = password === user.password;
      if (passwordValid) {
        const hashed = await bcrypt.hash(password, 10);
        await pool.query('UPDATE users SET password = $1 WHERE id = $2', [hashed, user.id]);
        console.log(`🔒 Migrated user ${user.id} from plaintext to hashed password`);
      }
    }

    if (!passwordValid) {
      return res.status(401).json({ status: 'error', message: 'Invalid credentials' });
    }
    
    const userRole = user.role;
    const finalDeviceId = deviceId || req.headers['user-agent'] || 'unknown';
    const finalDeviceName = deviceName || 'Unknown Device';
    
    // 🔐 Resolve company ownership for this user
    let isOwner = false;
    if (user.company_id) {
      try {
        const ownRow = await pool.query('SELECT owner_id FROM companies WHERE id = $1', [user.company_id]);
        isOwner = ownRow.rows.length > 0 && ownRow.rows[0].owner_id === user.id;
      } catch (e) {
        console.log('⚠️ Owner lookup failed:', e.message);
      }
    }
    
    // ✅ Clean expired sessions
    await pool.query(
      `UPDATE user_sessions 
       SET is_active = false, terminated_at = NOW() 
       WHERE expires_at < NOW() AND is_active = true`
    );
    
    // ✅ Check if user already has an active session
    const existingSession = await pool.query(
      `SELECT * FROM user_sessions 
       WHERE user_id = $1 AND is_active = true AND expires_at > NOW()`,
      [user.id]
    );
    
    // ✅ If no existing session → Login normally
    if (existingSession.rows.length === 0) {
      const sessionToken = generateSessionToken();
      await pool.query(
        `INSERT INTO user_sessions (user_id, session_token, device_id, device_name, is_active, expires_at)
         VALUES ($1, $2, $3, $4, true, NOW() + INTERVAL '8 hours')`,
        [user.id, sessionToken, finalDeviceId, finalDeviceName]
      );
      
      await pool.query('UPDATE users SET last_login = CURRENT_TIMESTAMP WHERE id = $1', [user.id]);
      
      return res.json({
        status: 'success',
        message: 'Login successful',
        data: {
          user: {
            id: user.id,
            _id: user.id,
            username: user.username,
            email: user.email,
            role: user.role,
            companyId: user.company_id,
            isActive: user.is_active,
            emailVerified: user.email_verified,
            isOwner: isOwner
          },
          sessionToken: sessionToken,
          deviceId: finalDeviceId,
          deviceName: finalDeviceName
        }
      });
    }
    
    const activeSession = existingSession.rows[0];
    
    // ✅ If Manager or Admin → Auto-terminate old session (always allowed)
    if (userRole === 'Manager' || userRole === 'Administrator') {
      await pool.query(
        'UPDATE user_sessions SET is_active = false, terminated_at = NOW() WHERE user_id = $1 AND is_active = true',
        [user.id]
      );
      
      const sessionToken = generateSessionToken();
      await pool.query(
        `INSERT INTO user_sessions (user_id, session_token, device_id, device_name, is_active, expires_at)
         VALUES ($1, $2, $3, $4, true, NOW() + INTERVAL '8 hours')`,
        [user.id, sessionToken, finalDeviceId, finalDeviceName]
      );
      
      await pool.query('UPDATE users SET last_login = CURRENT_TIMESTAMP WHERE id = $1', [user.id]);
      
      return res.json({
        status: 'success',
        message: 'Login successful (previous session terminated)',
        data: {
          user: {
            id: user.id,
            _id: user.id,
            username: user.username,
            email: user.email,
            role: user.role,
            companyId: user.company_id,
            isActive: user.is_active,
            emailVerified: user.email_verified,
            isOwner: isOwner
          },
          sessionToken: sessionToken,
          deviceId: finalDeviceId,
          deviceName: finalDeviceName,
          previousDeviceTerminated: true,
        }
      });
    }
    
    // ✅ If Staff → Needs Manager Approval
    if (userRole === 'Staff') {
      // Check if there's already a pending request
      const pendingRequest = await pool.query(
        `SELECT * FROM login_requests 
         WHERE user_id = $1 AND status = 'pending' AND expires_at > NOW()`,
        [user.id]
      );
      
      if (pendingRequest.rows.length > 0) {
        const existing = pendingRequest.rows[0];
        
        // If same device, return existing request
        if (existing.device_id === finalDeviceId) {
          return res.json({
            status: 'pending',
            message: 'Approval request already sent to manager. Please wait.',
            requestToken: existing.request_token,
            deviceName: existing.device_name,
          });
        }
        
        // Different device - expire old request
        await pool.query(
          `UPDATE login_requests SET status = 'expired', terminated_at = NOW() WHERE request_token = $1`,
          [existing.request_token]
        );
      }
      
      // ✅ Create a pending session request
      const requestToken = 'request_' + user.id + '_' + Date.now();
      
      await pool.query(
        `INSERT INTO login_requests (
          user_id, 
          request_token, 
          device_id, 
          device_name, 
          status,
          request_time,
          expires_at,
          existing_session_token
        ) VALUES ($1, $2, $3, $4, 'pending', CURRENT_TIMESTAMP, NOW() + INTERVAL '15 minutes', $5)`,
        [user.id, requestToken, finalDeviceId, finalDeviceName, activeSession.session_token]
      );
      
      // Get managers for notification
      const managers = await pool.query(
        `SELECT id, username FROM users 
         WHERE company_id = $1 AND (role = 'Manager' OR role = 'Administrator')`,
        [user.company_id]
      );
      
      console.log(`📢 Login request from ${user.username} on ${finalDeviceName}`);
      console.log(`👥 Notify managers: ${managers.rows.map(m => m.username).join(', ')}`);
      
      return res.json({
        status: 'pending',
        message: 'Approval request sent to manager. Please wait.',
        requestToken: requestToken,
        deviceName: finalDeviceName,
        managers: managers.rows,
      });
    }
    
    // ✅ Customer login with existing session - create new session (allow multiple devices)
    if (userRole === 'Customer') {
      const sessionToken = generateSessionToken();
      await pool.query(
        `INSERT INTO user_sessions (user_id, session_token, device_id, device_name, is_active, expires_at)
         VALUES ($1, $2, $3, $4, true, NOW() + INTERVAL '8 hours')`,
        [user.id, sessionToken, finalDeviceId, finalDeviceName]
      );
      
      await pool.query('UPDATE users SET last_login = CURRENT_TIMESTAMP WHERE id = $1', [user.id]);
      
      return res.json({
        status: 'success',
        message: 'Login successful',
        data: {
          user: {
            id: user.id,
            _id: user.id,
            username: user.username,
            email: user.email,
            role: user.role,
            companyId: user.company_id,
            isActive: user.is_active,
            emailVerified: user.email_verified,
            isOwner: isOwner
          },
          sessionToken: sessionToken,
          deviceId: finalDeviceId,
          deviceName: finalDeviceName
        }
      });
    }
    
    // Fallback (should not reach here)
    return res.status(400).json({ 
      status: 'error', 
      message: 'Unable to process login request' 
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
    resetCodes[email] = { code, userId: user.id, expiresAt: Date.now() + 10 * 60 * 1000, type: 'verify' };
    await sendVerificationEmail(email, code, user.username);
    console.log(`📧 Verification email resent to ${email}`);
    
    res.json({ status: 'success', message: 'Verification email sent!' });
  } catch (error) {
    res.status(500).json({ status: 'error', message: error.message });
  }
});

// GET PROFILE (requires valid session — identity comes from the token, not the client)
app.get('/api/auth/me', requireSession(pool), async (req, res) => {
  try {
    const userId = req.user.id;
    
    const result = await pool.query(
      `SELECT u.id, u.username, u.email, u.role, u.company_id, u.is_active, u.last_login, u.created_at,
              (c.owner_id = u.id) AS is_owner
       FROM users u
       LEFT JOIN companies c ON c.id = u.company_id
       WHERE u.id = $1`,
      [userId]
    );
    
    if (result.rows.length === 0) return res.status(404).json({ status: 'error', message: 'User not found' });
    
    const user = result.rows[0];
    res.json({
      status: 'success',
      data: {
        user: {
          id: user.id, _id: user.id, username: user.username,
          email: user.email, role: user.role, companyId: user.company_id,
          isActive: user.is_active, lastLogin: user.last_login, createdAt: user.created_at,
          isOwner: user.is_owner === true
        }
      }
    });
  } catch (error) {
    res.status(500).json({ status: 'error', message: error.message });
  }
});

// ✅ LOGOUT - Invalidate session
app.post('/api/auth/logout', async (req, res) => {
  try {
    const authHeader = req.headers.authorization;
    if (authHeader && authHeader.startsWith('Bearer ')) {
      const token = authHeader.split(' ')[1];
      if (token) {
        await pool.query(
          'UPDATE user_sessions SET is_active = false, expires_at = NOW(), terminated_at = NOW() WHERE session_token = $1',
          [token]
        );
        console.log('🔓 Session invalidated:', token.substring(0, 20) + '...');
      }
    }
    
    res.json({ status: 'success', message: 'Logged out successfully' });
  } catch (error) {
    console.error('❌ Logout error:', error);
    res.json({ status: 'success', message: 'Logged out successfully' });
  }
});

// CREATE STAFF (Admin & Manager — requires valid session)
app.post('/api/auth/create-staff', requireSession(pool), async (req, res) => {
  try {
    const { username, email, password, securityQuestions } = req.body;
    const creatorId = req.user.id;
    console.log(`👤 Creating staff: ${username} by user ID: ${creatorId}`);
    
    const existing = await pool.query('SELECT id FROM users WHERE username = $1 OR email = $2', [username, email]);
    if (existing.rows.length > 0) {
      return res.status(400).json({ status: 'error', message: 'Username or email already exists' });
    }
    
    // 🔒 Only Manager/Administrator can create staff
    if (!['Manager', 'Administrator'].includes(req.user.role)) {
      return res.status(403).json({ status: 'error', message: 'Only managers and administrators can create staff' });
    }
    
    const companyId = req.user.company_id;
    console.log(`🏢 Creator company_id: ${companyId}`);
    
    // 🔐 Resolve whether the creator is the company owner
    let creatorIsOwner = false;
    try {
      const ownRow = await pool.query('SELECT owner_id FROM companies WHERE id = $1', [companyId]);
      creatorIsOwner = ownRow.rows.length > 0 && ownRow.rows[0].owner_id === creatorId;
    } catch (e) { /* owner column may not exist yet */ }
    
    // 🔒 Hash the password before storing
    const hashedPassword = await bcrypt.hash(password, 10);

    // 🔐 OWNERS can add staff instantly. Co-managers' additions require the
    // owner to verify with the code emailed to them (join request flow).
    if (!creatorIsOwner && req.user.role !== 'Administrator') {
      const created = await pool.query(
        `INSERT INTO users (username, email, password, role, company_id, security_question1, security_question2) 
         VALUES ($1, $2, $3, 'Customer', NULL, $4, $5) 
         RETURNING id`,
        [username, email, hashedPassword,
         securityQuestions?.question1 || '', securityQuestions?.question2 || '']
      );
      const pendingUser = created.rows[0];
      const joinCode = Math.floor(100000 + Math.random() * 900000).toString();
      await pool.query(
        `INSERT INTO company_join_requests (company_id, user_id, requested_role, code, status, expires_at)
         VALUES ($1, $2, 'Staff', $3, 'pending', NOW() + INTERVAL '15 minutes')`,
        [companyId, pendingUser.id, joinCode]
      );
      // Email the code to the company owner
      try {
        const compRow = await pool.query(
          `SELECT c.name, c.email AS company_email, u.email AS owner_email
           FROM companies c LEFT JOIN users u ON u.id = c.owner_id WHERE c.id = $1`, [companyId]);
        const ownerEmail = compRow.rows[0]?.owner_email || compRow.rows[0]?.company_email;
        if (ownerEmail) {
          await sendJoinRequestEmail(ownerEmail, compRow.rows[0].name, username, compRow.rows[0].name, joinCode, 'Staff');
        }
      } catch (e) { console.log('⚠️ Join request email failed:', e.message); }
      
      return res.status(202).json({
        status: 'pending_approval',
        message: 'Staff created but pending owner verification. The owner received a code by email.',
        data: { userId: pendingUser.id, pendingApproval: true }
      });
    }

    const result = await pool.query(
      `INSERT INTO users (username, email, password, role, company_id, security_question1, security_question2) 
       VALUES ($1, $2, $3, 'Staff', $4, $5, $6) 
       RETURNING id, username, email, role, company_id, is_active, created_at`,
      [username, email, hashedPassword, companyId, 
       securityQuestions?.question1 || '', securityQuestions?.question2 || '']
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
app.post('/api/auth/block-user/:id', requireSession(pool), async (req, res) => {
  try {
    const userId = req.params.id;
    const userResult = await pool.query('SELECT id, username, role, company_id FROM users WHERE id = $1', [userId]);
    if (userResult.rowCount === 0) return res.status(404).json({ status: 'error', message: 'User not found' });
    
    const user = userResult.rows[0];
    if (user.role === 'Administrator') return res.status(403).json({ status: 'error', message: 'Cannot block Administrator' });
    
    const isAdmin = req.user?.role === 'Administrator';

    // 🔒 Non-admins may only manage users inside their own company
    if (!isAdmin && req.user?.company_id != null && user.company_id != null && user.company_id !== req.user.company_id) {
      return res.status(403).json({ status: 'error', message: 'You can only manage users in your own company' });
    }

    // 🔒 Only the company owner or an Administrator can block another Manager
    if (user.role === 'Manager' && !isAdmin) {
      let isOwner = false;
      try {
        const ownRow = await pool.query('SELECT owner_id FROM companies WHERE id = $1', [user.company_id]);
        isOwner = ownRow.rows.length > 0 && ownRow.rows[0].owner_id === req.user?.id;
      } catch (e) { /* owner column may not exist yet */ }
      if (!isOwner) {
        return res.status(403).json({ status: 'error', message: 'Only the company owner can block another manager' });
      }
    }

    // 🔐 Company owners cannot be blocked by other managers
    if (req.user?.company_id) {
      try {
        const ownRow = await pool.query('SELECT owner_id FROM companies WHERE id = $1', [req.user.company_id]);
        if (ownRow.rows.length > 0 && ownRow.rows[0].owner_id === user.id) {
          return res.status(403).json({ status: 'error', message: 'Cannot block the company owner' });
        }
      } catch (e) { /* owner column may not exist yet — fail open */ }
    }
    
    const result = await pool.query(
      'UPDATE users SET is_active = false, updated_at = CURRENT_TIMESTAMP WHERE id = $1 RETURNING id, username, email, role, is_active',
      [userId]
    );
    
    res.json({ status: 'success', message: `${result.rows[0].username} blocked`, data: { user: { id: result.rows[0].id, username: result.rows[0].username, role: result.rows[0].role, isActive: false } } });
  } catch (error) {
    res.status(500).json({ status: 'error', message: error.message });
  }
});

// UNBLOCK USER
app.post('/api/auth/unblock-user/:id', requireSession(pool), async (req, res) => {
  try {
    const userId = req.params.id;
    const userResult = await pool.query('SELECT id, company_id, role FROM users WHERE id = $1', [userId]);
    if (userResult.rowCount === 0) return res.status(404).json({ status: 'error', message: 'User not found' });

    const user = userResult.rows[0];
    const isAdmin = req.user?.role === 'Administrator';

    // 🔒 Non-admins may only manage users inside their own company
    if (!isAdmin && req.user?.company_id != null && user.company_id != null && user.company_id !== req.user.company_id) {
      return res.status(403).json({ status: 'error', message: 'You can only manage users in your own company' });
    }

    // 🔒 Only the company owner or an Administrator can unblock another Manager
    if (user.role === 'Manager' && !isAdmin) {
      let isOwner = false;
      try {
        const ownRow = await pool.query('SELECT owner_id FROM companies WHERE id = $1', [user.company_id]);
        isOwner = ownRow.rows.length > 0 && ownRow.rows[0].owner_id === req.user?.id;
      } catch (e) { /* owner column may not exist yet */ }
      if (!isOwner) {
        return res.status(403).json({ status: 'error', message: 'Only the company owner can unblock another manager' });
      }
    }
    
    const result = await pool.query(
      'UPDATE users SET is_active = true, updated_at = CURRENT_TIMESTAMP WHERE id = $1 RETURNING id, username, email, role, is_active',
      [userId]
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

// GET USERS (requires session; only Manager/Administrator; Managers see their own company)
app.get('/api/users', requireSession(pool), async (req, res) => {
  try {
    const { role, search } = req.query;
    const requesterRole = req.user.role;
    
    // 🔒 Only Manager/Administrator can list users
    if (!['Manager', 'Administrator'].includes(requesterRole)) {
      return res.status(403).json({ status: 'error', message: 'Not authorized to list users' });
    }
    
    let query = 'SELECT id, username, email, role, company_id, is_active, created_at, last_login FROM users WHERE 1=1';
    const params = [];
    let p = 1;
    
    if (role) { query += ` AND role = $${p}`; params.push(role); p++; }
    if (search) { query += ` AND (username ILIKE $${p} OR email ILIKE $${p})`; params.push(`%${search}%`); p++; }
    if (requesterRole === 'Manager') {
      const managerCompanyId = req.user.company_id;
      if (managerCompanyId) {
        query += ` AND company_id = $${p}`;
        params.push(managerCompanyId);
        p++;
        console.log(`🔒 Filtering by company_id: ${managerCompanyId}`);
      }
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

// GET DRINKS FROM DATABASE (requires valid session)
app.get('/api/drinks', requireSession(pool), async (req, res) => {
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
    // Missing table is a recoverable "no data yet" state — report it honestly.
    if (error.message && error.message.includes('does not exist')) {
      return res.json({
        success: true,
        count: 0,
        drinks: [],
        message: 'No drinks table yet. Create one or use the app to add drinks.'
      });
    }
    console.error('❌ Drinks query error:', error.message);
    res.status(500).json({ success: false, message: 'Failed to load drinks' });
  }
});

app.get('/api/test', (req, res) => {
  res.json({ success: true, message: 'DrinkQuick API v3.0', working: true, database: 'Supabase PostgreSQL', email: 'Enabled' });
});

app.get('/api/ping', (req, res) => {
  res.json({ success: true, message: 'pong' });
});

app.get('/', (req, res) => {
  res.json({ success: true, message: 'DrinkQuick API 🍹', version: '3.0', status: '🟢 ONLINE', database: 'Supabase PostgreSQL' });
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
app.get('/api/auth/confirm-email', async (req, res) => {
  try {
    const { email, code } = req.query;
    
    console.log(`📧 Verification request: email=${email}, code=${code}`);
    
    if (!email || !code) {
      return res.status(400).send(`
        <!DOCTYPE html>
        <html>
          <head><title>Invalid Link</title></head>
          <body style="font-family:Arial;text-align:center;padding:50px;">
            <h2 style="color:red;">❌ Invalid Verification Link</h2>
            <p>The verification link is missing required information.</p>
            <a href="https://drink-quick-cal-kja1.onrender.com" style="color:#667EEA;">Go to App</a>
          </body>
        </html>
      `);
    }
    
    const stored = resetCodes[email];
    
    if (!stored) {
      console.log(`❌ No verification code found for: ${email}`);
      return res.status(400).send(`
        <!DOCTYPE html>
        <html>
          <head><title>Code Expired</title></head>
          <body style="font-family:Arial;text-align:center;padding:50px;">
            <h2 style="color:orange;">⏳ Code Expired</h2>
            <p>No verification code found. Please request a new one.</p>
            <a href="https://drink-quick-cal-kja1.onrender.com" style="color:#667EEA;">Go to App</a>
          </body>
        </html>
      `);
    }
    
    if (stored.code !== code) {
      console.log(`❌ Invalid code for: ${email}`);
      return res.status(400).send(`
        <!DOCTYPE html>
        <html>
          <head><title>Invalid Code</title></head>
          <body style="font-family:Arial;text-align:center;padding:50px;">
            <h2 style="color:red;">❌ Invalid Code</h2>
            <p>The verification code is incorrect.</p>
            <a href="https://drink-quick-cal-kja1.onrender.com" style="color:#667EEA;">Go to App</a>
          </body>
        </html>
      `);
    }
    
    if (Date.now() > stored.expiresAt) {
      console.log(`❌ Code expired for: ${email}`);
      delete resetCodes[email];
      return res.status(400).send(`
        <!DOCTYPE html>
        <html>
          <head><title>Code Expired</title></head>
          <body style="font-family:Arial;text-align:center;padding:50px;">
            <h2 style="color:orange;">⏳ Code Expired</h2>
            <p>The verification code has expired (10 minutes). Please request a new one.</p>
            <a href="https://drink-quick-cal-kja1.onrender.com" style="color:#667EEA;">Go to App</a>
          </body>
        </html>
      `);
    }
    
    console.log(`✅ Verifying email for user ID: ${stored.userId}`);
    
    await pool.query(
      'UPDATE users SET email_verified = true WHERE id = $1',
      [stored.userId]
    );
    
    delete resetCodes[email];
    
    console.log(`✅ Email verified for: ${email}`);
    
    res.send(`
      <!DOCTYPE html>
      <html>
        <head>
          <title>Email Verified ✅</title>
          <style>
            body {
              font-family: Arial, sans-serif;
              text-align: center;
              padding: 50px;
              background: #f5f5f5;
              margin: 0;
            }
            .container {
              max-width: 400px;
              margin: 0 auto;
              background: white;
              padding: 40px;
              border-radius: 15px;
              box-shadow: 0 4px 15px rgba(0,0,0,0.1);
            }
            h1 { color: #4CAF50; }
            .btn {
              display: inline-block;
              background: #667EEA;
              color: white;
              padding: 12px 30px;
              border-radius: 10px;
              text-decoration: none;
              margin-top: 20px;
            }
            .btn:hover { background: #5a6fd6; }
          </style>
        </head>
        <body>
          <div class="container">
            <h1>✅ Email Verified!</h1>
            <p>Your email has been successfully verified.</p>
            <p>You can now login to your account.</p>
            <a href="https://drink-quick-cal-kja1.onrender.com" class="btn">Go to App</a>
          </div>
        </body>
      </html>
    `);
    
  } catch (error) {
    console.error('❌ Verification error:', error);
    res.status(500).send(`
      <!DOCTYPE html>
      <html>
        <head><title>Error</title></head>
        <body style="font-family:Arial;text-align:center;padding:50px;">
          <h2 style="color:red;">❌ Verification Failed</h2>
          <p>An error occurred. Please try again later.</p>
          <a href="https://drink-quick-cal-kja1.onrender.com" style="color:#667EEA;">Go to App</a>
        </body>
      </html>
    `);
  }
});

// VERIFY COMPANY INVITE CODE
app.post('/api/companies/verify-code', async (req, res) => {
  try {
    const { code } = req.body;
    if (!code) return res.status(400).json({ status: 'error', message: 'Invite code required' });
    
    const result = await pool.query(
      'SELECT id, name, code FROM companies WHERE (invite_code = $1 OR code = $1) AND is_active = true',
      [code.toUpperCase()]
    );
    
    if (result.rows.length === 0) {
      return res.status(404).json({ status: 'error', message: 'Invalid invite code. Company not found.' });
    }
    
    res.json({ status: 'success', data: { company: result.rows[0] } });
  } catch (error) {
    res.status(500).json({ status: 'error', message: error.message });
  }
});

// ========== SESSION VALIDATION ==========
app.post('/api/auth/validate-session', async (req, res) => {
  try {
    const authHeader = req.headers.authorization;
    if (!authHeader || !authHeader.startsWith('Bearer ')) {
      return res.json({ valid: false, terminated: false });
    }
    
    const token = authHeader.split(' ')[1];
    if (!token) {
      return res.json({ valid: false, terminated: false });
    }
    
    console.log('🔍 Validating token:', token.substring(0, 20) + '...');
    
    // Clean expired sessions
    await pool.query(
      `UPDATE user_sessions 
       SET is_active = false, terminated_at = NOW() 
       WHERE expires_at < NOW() AND is_active = true`
    );
    
    // Check in database
    const session = await pool.query(
      `SELECT s.*, u.username 
       FROM user_sessions s
       JOIN users u ON s.user_id = u.id
       WHERE s.session_token = $1 AND s.is_active = true AND s.expires_at > NOW()`,
      [token]
    );
    
    if (session.rows.length > 0) {
      console.log('✅ Session found in database for user:', session.rows[0].username);
      
      await pool.query(
        'UPDATE user_sessions SET last_activity_at = CURRENT_TIMESTAMP WHERE session_token = $1',
        [token]
      );
      
      return res.json({ 
        valid: true, 
        terminated: false,
        previousDeviceName: null
      });
    }
    
    // Check token format as fallback
    const tokenParts = token.split('_');
    if (tokenParts.length >= 2 && tokenParts[0] === 'token') {
      const userId = parseInt(tokenParts[1]);
      if (!isNaN(userId) && userId > 0) {
        console.log('⚠️ Token format valid but not in database');
        return res.json({ 
          valid: false, 
          terminated: false,
          message: 'Session not found in database'
        });
      }
    }
    
    console.log('❌ Invalid session token');
    res.json({ valid: false, terminated: false });
    
  } catch (error) {
    console.error('❌ Validate session error:', error);
    res.json({ valid: false, terminated: false });
  }
});

// ========== MANAGER APPROVAL SYSTEM ==========

// 🔐 GET PENDING JOIN REQUESTS (owner/manager of the company, or Administrator)
app.get('/api/auth/pending-joins', requireSession(pool), async (req, res) => {
  try {
    const isAdmin = req.user.role === 'Administrator';
    if (req.user.role !== 'Manager' && req.user.role !== 'Administrator') {
      return res.status(403).json({ status: 'error', message: 'Only managers can view join requests' });
    }
    
    // Expire stale pending requests first
    await pool.query(`
      UPDATE company_join_requests SET status = 'expired', resolved_at = NOW()
      WHERE status = 'pending' AND expires_at < NOW()
    `);
    
    const params = [];
    let where = `j.status = 'pending' AND j.expires_at > NOW()`;
    if (!isAdmin) {
      params.push(req.user.company_id);
      where += ` AND j.company_id = $1`;
    }
    
    const rows = await pool.query(
      `SELECT j.id, j.company_id, j.requested_role, j.created_at, j.expires_at,
              u.id AS user_id, u.username, u.email
       FROM company_join_requests j
       JOIN users u ON u.id = j.user_id
       WHERE ${where}
       ORDER BY j.created_at DESC`,
      params
    );
    
    // Never expose the code itself to the app — the owner got it by email
    res.json({
      status: 'success',
      requests: rows.rows.map(r => ({
        id: r.id,
        companyId: r.company_id,
        userId: r.user_id,
        username: r.username,
        email: r.email,
        requestedRole: r.requested_role,
        createdAt: r.created_at,
        expiresAt: r.expires_at
      }))
    });
  } catch (error) {
    console.error('❌ Pending joins error:', error.message);
    res.status(500).json({ status: 'error', message: error.message });
  }
});

// 🔐 APPROVE/REJECT A JOIN REQUEST — owner enters the emailed code.
//    Administrators can override (no code required).
app.post('/api/auth/approve-join/:id', requireSession(pool), async (req, res) => {
  try {
    const requestId = parseInt(req.params.id, 10);
    const { code, approved } = req.body;
    const approverId = req.user.id;
    const isAdmin = req.user.role === 'Administrator';
    
    const reqRow = await pool.query('SELECT * FROM company_join_requests WHERE id = $1', [requestId]);
    if (reqRow.rows.length === 0) return res.status(404).json({ status: 'error', message: 'Join request not found' });
    const joinReq = reqRow.rows[0];
    
    if (joinReq.status !== 'pending') {
      return res.status(400).json({ status: 'error', message: `Request already ${joinReq.status}` });
    }
    if (joinReq.expires_at && new Date(joinReq.expires_at) < new Date()) {
      await pool.query(`UPDATE company_join_requests SET status = 'expired', resolved_at = NOW() WHERE id = $1`, [requestId]);
      // Option (a): expired pending account is deleted
      await pool.query('DELETE FROM users WHERE id = $1', [joinReq.user_id]);
      return res.status(400).json({ status: 'error', message: 'Request expired. The pending account was deleted.' });
    }
    
    // 🔒 Authorization: company owner OR Administrator (override)
    let isOwner = false;
    const ownRow = await pool.query('SELECT owner_id FROM companies WHERE id = $1', [joinReq.company_id]);
    if (ownRow.rows.length > 0 && ownRow.rows[0].owner_id === approverId) isOwner = true;
    if (!isOwner && !isAdmin) {
      return res.status(403).json({ status: 'error', message: 'Only the company owner can verify join requests' });
    }
    
    if (!approved) {
      // REJECT → mark rejected and DELETE the pending account (option a)
      await pool.query(`UPDATE company_join_requests SET status = 'rejected', approved_by = $1, resolved_at = NOW() WHERE id = $2`, [approverId, requestId]);
      await pool.query('DELETE FROM users WHERE id = $1', [joinReq.user_id]);
      console.log(`🚫 Join request #${requestId} rejected by user ${approverId} — pending account deleted`);
      return res.json({ status: 'success', message: 'Request rejected. The pending account has been deleted.' });
    }
    
    // APPROVE → verify code (owners must supply it; Administrators override)
    if (!isAdmin) {
      if (!code) return res.status(400).json({ status: 'error', message: 'Verification code required' });
      if ((joinReq.attempts || 0) >= 5) {
        await pool.query(`UPDATE company_join_requests SET status = 'expired', resolved_at = NOW() WHERE id = $1`, [requestId]);
        await pool.query('DELETE FROM users WHERE id = $1', [joinReq.user_id]);
        return res.status(429).json({ status: 'error', message: 'Too many wrong attempts. Request cancelled and account deleted.' });
      }
      if (String(code).trim() !== String(joinReq.code)) {
        await pool.query('UPDATE company_join_requests SET attempts = attempts + 1 WHERE id = $1', [requestId]);
        return res.status(400).json({ status: 'error', message: 'Wrong verification code' });
      }
    }
    
    // ✅ Approve: link the user to the company with the requested role
    await pool.query(
      `UPDATE users SET company_id = $1, role = $2, updated_at = CURRENT_TIMESTAMP WHERE id = $3`,
      [joinReq.company_id, joinReq.requested_role, joinReq.user_id]
    );
    await pool.query(
      `UPDATE company_join_requests SET status = 'approved', approved_by = $1, resolved_at = NOW() WHERE id = $2`,
      [approverId, requestId]
    );
    
    const approvedUser = await pool.query('SELECT username, email FROM users WHERE id = $1', [joinReq.user_id]);
    try {
      if (approvedUser.rows.length > 0) {
        await sendWelcomeEmail(approvedUser.rows[0].email, approvedUser.rows[0].username);
      }
    } catch (e) { /* non-fatal */ }
    
    console.log(`✅ Join request #${requestId} approved by ${isAdmin ? 'ADMIN (override)' : 'owner'} user ${approverId}`);
    res.json({
      status: 'success',
      message: isAdmin ? 'Approved by administrator override' : 'Member approved and added to your company',
      data: { userId: joinReq.user_id, role: joinReq.requested_role, companyId: joinReq.company_id }
    });
  } catch (error) {
    console.error('❌ Approve join error:', error.message);
    res.status(500).json({ status: 'error', message: error.message });
  }
});

// ✅ Get pending requests (for Manager)
app.get('/api/auth/pending-requests', async (req, res) => {
  try {
    const authHeader = req.headers.authorization;
    const token = authHeader && authHeader.startsWith('Bearer ') ? authHeader.split(' ')[1] : null;
    const sessionUser = await getSessionUser(pool, token);
    if (!sessionUser) {
      return res.status(401).json({ status: 'error', message: 'Invalid or expired session' });
    }
    
    const managerId = sessionUser.id;
    
    const manager = await pool.query(
      'SELECT id, username, company_id, role FROM users WHERE id = $1',
      [managerId]
    );
    
    if (manager.rows.length === 0) {
      return res.status(404).json({ status: 'error', message: 'User not found' });
    }
    
    if (manager.rows[0].role !== 'Manager' && manager.rows[0].role !== 'Administrator') {
      return res.status(403).json({ status: 'error', message: 'Only managers can view pending requests' });
    }
    
    const companyId = manager.rows[0].company_id;
    
    // ✅ Get pending requests with staff info
    const pendingRequests = await pool.query(
      `SELECT 
        lr.*, 
        u.id as staff_id,
        u.username as staff_username
       FROM login_requests lr
       JOIN users u ON lr.user_id = u.id
       WHERE lr.status = 'pending' 
         AND lr.expires_at > NOW()
         AND u.company_id = $1
       ORDER BY lr.request_time DESC`,
      [companyId]
    );
    
    res.json({
      status: 'success',
      requests: pendingRequests.rows.map(row => ({
        ...row,
        staff_id: row.staff_id,
        staff_username: row.staff_username,
      })),
    });
    
  } catch (error) {
    console.error('❌ Pending requests error:', error);
    res.status(500).json({ status: 'error', message: 'Failed to get pending requests' });
  }
});

// ✅ Check approval status (for Staff)
app.get('/api/auth/check-approval', async (req, res) => {
  try {
    const { token } = req.query;
    
    if (!token) {
      return res.status(400).json({ status: 'error', message: 'Request token required' });
    }
    
    const request = await pool.query(
      `SELECT status, new_session_token, device_name, user_id
       FROM login_requests 
       WHERE request_token = $1`,
      [token]
    );
    
    if (request.rows.length === 0) {
      return res.status(404).json({ status: 'error', message: 'Request not found' });
    }
    
    const requestData = request.rows[0];
    
    res.json({
      status: 'success',
      approvalStatus: requestData.status,
      sessionToken: requestData.new_session_token,
      deviceName: requestData.device_name,
    });
    
  } catch (error) {
    console.error('❌ Check approval error:', error);
    res.status(500).json({ status: 'error', message: 'Failed to check approval status' });
  }
});

// ✅ Approve or reject login (Manager) - FIXED
app.post('/api/auth/approve-login', async (req, res) => {
  try {
    const { requestToken, approved } = req.body;
    
    if (!requestToken || approved === undefined) {
      return res.status(400).json({ status: 'error', message: 'Missing required fields' });
    }
    
    // 🔒 Manager identity comes from the session token, not the client body
    const authHeader = req.headers.authorization;
    const sessionToken = authHeader && authHeader.startsWith('Bearer ') ? authHeader.split(' ')[1] : null;
    const sessionUser = await getSessionUser(pool, sessionToken);
    if (!sessionUser) {
      return res.status(401).json({ status: 'error', message: 'Invalid or expired session' });
    }
    const managerId = sessionUser.id;
    
    // ✅ Get manager info FIRST
    const managerCheck = await pool.query(
      'SELECT id, username, role, company_id FROM users WHERE id = $1',
      [managerId]
    );
    
    if (managerCheck.rows.length === 0) {
      return res.status(404).json({ status: 'error', message: 'Manager not found' });
    }
    
    const manager = managerCheck.rows[0];
    if (manager.role !== 'Manager' && manager.role !== 'Administrator') {
      return res.status(403).json({ status: 'error', message: 'Only managers can approve logins' });
    }
    
    // ✅ Get the pending request with staff info
    const request = await pool.query(
      `SELECT 
        lr.*, 
        u.id as staff_id,
        u.username as staff_username
       FROM login_requests lr
       JOIN users u ON lr.user_id = u.id
       WHERE lr.request_token = $1 AND lr.status = 'pending'`,
      [requestToken]
    );
    
    if (request.rows.length === 0) {
      return res.status(404).json({ status: 'error', message: 'Request not found or already processed' });
    }
    
    const requestData = request.rows[0];
    const userId = requestData.user_id;
    const existingSessionToken = requestData.existing_session_token;
    const staffId = requestData.staff_id;
    const staffName = requestData.staff_username || 'Unknown Staff';
    const deviceName = requestData.device_name || 'Unknown Device';
    const managerName = manager.username || 'Unknown Manager';

    console.log(`👤 Manager: ${managerName} (ID: ${managerId})`);
    console.log(`👤 Staff: ${staffName} (ID: ${staffId})`);
    console.log(`📱 Device: ${deviceName}`);
    console.log(`📝 Action: ${approved ? 'APPROVED' : 'REJECTED'}`);

    if (approved) {
      // ✅ TERMINATE the existing session
      if (existingSessionToken) {
        await pool.query(
          'UPDATE user_sessions SET is_active = false, terminated_at = NOW() WHERE session_token = $1',
          [existingSessionToken]
        );
        console.log(`🔒 Session terminated: ${existingSessionToken}`);
      }
      
      // ✅ Create NEW session
      const newSessionToken = generateSessionToken();
      await pool.query(
        `INSERT INTO user_sessions (user_id, session_token, device_id, device_name, is_active, expires_at)
         VALUES ($1, $2, $3, $4, true, NOW() + INTERVAL '8 hours')`,
        [userId, newSessionToken, requestData.device_id, requestData.device_name]
      );
      
      // ✅ Mark request as approved
      await pool.query(
        `UPDATE login_requests 
         SET status = 'approved', 
             approved_by = $1,
             approved_at = CURRENT_TIMESTAMP,
             new_session_token = $2
         WHERE request_token = $3`,
        [managerId, newSessionToken, requestToken]
      );
      
      // ✅ Log the approval with ALL data
      await pool.query(
        `INSERT INTO approval_logs (
          request_token, 
          manager_id, 
          staff_id, 
          staff_name, 
          device_name, 
          action, 
          details, 
          timestamp
        ) VALUES ($1, $2, $3, $4, $5, 'approved', $6, CURRENT_TIMESTAMP)`,
        [
          requestToken,
          managerId,           // ✅ Manager ID
          staffId,             // ✅ Staff ID (FIXED)
          staffName,           // ✅ Staff Name
          deviceName,          // ✅ Device Name
          `✅ Approved by ${managerName} - Staff ${staffName} on ${deviceName}`
        ]
      );
      
      return res.json({
        status: 'success',
        message: '✅ Login approved! Old session terminated.',
        sessionToken: newSessionToken,
        deviceName: requestData.device_name,
        managerName: managerName,
        staffName: staffName,
      });
      
    } else {
      // ❌ Reject the request
      await pool.query(
        `UPDATE login_requests 
         SET status = 'rejected', 
             approved_by = $1,
             approved_at = CURRENT_TIMESTAMP
         WHERE request_token = $2`,
        [managerId, requestToken]
      );
      
      // ✅ Log the rejection with ALL data
      await pool.query(
        `INSERT INTO approval_logs (
          request_token, 
          manager_id, 
          staff_id, 
          staff_name, 
          device_name, 
          action, 
          details, 
          timestamp
        ) VALUES ($1, $2, $3, $4, $5, 'rejected', $6, CURRENT_TIMESTAMP)`,
        [
          requestToken,
          managerId,           // ✅ Manager ID
          staffId,             // ✅ Staff ID (FIXED)
          staffName,           // ✅ Staff Name
          deviceName,          // ✅ Device Name
          `❌ Rejected by ${managerName} - Staff ${staffName} on ${deviceName}`
        ]
      );
      
      return res.json({
        status: 'success',
        message: '❌ Login request rejected',
        managerName: managerName,
        staffName: staffName,
      });
    }
    
  } catch (error) {
    console.error('❌ Approval error:', error);
    res.status(500).json({ status: 'error', message: 'Approval failed' });
  }
});
// ========== PAYMENT ROUTES ==========
const paymentRoutes = require('./routes/payment.routes');
app.use('/api', paymentRoutes);

// ========== PUBLIC COMPANY PROFILE (no auth — customer mode) ==========
// Returns only non-secret fields so the anon key / unauthenticated users
// can render the order screen. API keys never leave the server.
app.get('/api/data/company/:id/public', async (req, res) => {
  try {
    const result = await pool.query(
      `SELECT id, name, email, phone, address, currency_symbol, currency_position,
              decimal_separator, thousands_separator, decimal_places,
              business_payments_enabled, mtn_enabled, orange_enabled,
              mtn_merchant_phone, orange_merchant_phone
       FROM companies WHERE id = $1`,
      [req.params.id]
    );
    if (result.rows.length === 0) {
      return res.status(404).json({ message: 'Company not found' });
    }
    res.json(result.rows[0]);
  } catch (error) {
    console.error('GET /api/data/company/:id/public error:', error.message);
    res.status(500).json({ message: 'Failed to load company' });
  }
});

// ========== DATA ROUTES (replaces direct Supabase REST access) ==========
const dataRoutes = require('./routes/data.routes');
app.use('/api/data', dataRoutes);

// ========== AI CHAT (Groq proxy — API key stays on server) ==========
app.post('/api/ai/chat', async (req, res) => {
  try {
    const authHeader = req.headers.authorization;
    const token = authHeader && authHeader.startsWith('Bearer ') ? authHeader.split(' ')[1] : null;
    const sessionUser = await getSessionUser(req.db, token);
    if (!sessionUser) {
      return res.status(401).json({ success: false, error: 'Invalid or expired session' });
    }
    const userId = sessionUser.id;

    const { prompt, history } = req.body || {};
    if (!prompt || typeof prompt !== 'string' || prompt.trim() === '') {
      return res.status(400).json({ success: false, error: 'Prompt is required' });
    }

    const apiKey = process.env.GROQ_API_KEY;
    if (!apiKey) {
      console.error('❌ GROQ_API_KEY not set on server');
      return res.status(500).json({ success: false, error: 'AI service not configured' });
    }

    const messages = [
      {
        role: 'system',
        content: 'You are a helpful drink ordering assistant for "Drink Quick Cal". Be concise, friendly, and helpful. Keep responses under 150 words.',
      },
      ...(Array.isArray(history) ? history : []),
      { role: 'user', content: prompt },
    ];

    const PREFERRED = [
      'llama3-8b-8192',
      'llama-3.3-70b-versatile',
      'llama-3.1-8b-instant',
      'llama-3.2-3b-preview',
      'llama3-70b-8192',
    ];

    // 🎯 Discover which Groq models this key can actually access.
    let availableModels = [];
    try {
      const modelsRes = await fetch('https://api.groq.com/openai/v1/models', {
        headers: { 'Authorization': `Bearer ${apiKey}` },
      });
      if (modelsRes.ok) {
        const modelsData = await modelsRes.json();
        availableModels = (modelsData.data || []).map((m) => m.id);
      }
    } catch (_) {}

    // Prefer a known-good model that the key has, else any compatible chat model.
    const candidates = PREFERRED.filter((id) => availableModels.includes(id));
    const models = candidates.length > 0
      ? candidates
      : (availableModels.filter((id) =>
            /^(llama|llama-3|llama-3\.|meta-|open-mixtral)/i.test(id)));

    if (models.length === 0) {
      console.error('❌ Groq: no usable chat model available for this key.');
      return res.status(502).json({ success: false, error: 'AI service has no available models' });
    }

    // Try candidate models in order; some accounts/plans may lack newer ones.
    let lastGroqError = null;
    for (const model of models) {
      try {
        const groqResponse = await fetch('https://api.groq.com/openai/v1/chat/completions', {
          method: 'POST',
          headers: {
            'Authorization': `Bearer ${apiKey}`,
            'Content-Type': 'application/json',
          },
          body: JSON.stringify({
            model,
            messages,
            temperature: 0.7,
            max_tokens: 500,
          }),
        });

        const data = await groqResponse.json();

        if (groqResponse.ok) {
          const content = (data.choices && data.choices[0] && data.choices[0].message
            ? data.choices[0].message.content
            : '').trim() || 'No response';
          return res.json({ success: true, content, model });
        }

        lastGroqError = { status: groqResponse.status, data };
        // If the model is unknown/unavailable, try the next candidate; otherwise stop.
        const modelErr = String(data?.error?.message || '').toLowerCase();
        const retryable = modelErr.includes('does not exist')
          || modelErr.includes('decommissioned')
          || modelErr.includes('no longer support')
          || modelErr.includes('not supported');
        if (!retryable) {
          break;
        }
      } catch (fetchErr) {
        lastGroqError = { status: 0, data: { error: { message: fetchErr.message } } };
      }
    }

    console.error('❌ Groq API error:', JSON.stringify(lastGroqError).slice(0, 400));
    return res.status(502).json({
      success: false,
      error: lastGroqError && lastGroqError.data && lastGroqError.data.error
        ? lastGroqError.data.error.message
        : 'AI request failed',
    });
  } catch (error) {
    console.error('❌ AI chat error:', error.message);
    return res.status(500).json({ success: false, error: 'Internal server error' });
  }
});

// ========== 404 ==========
app.use((req, res) => {
  res.status(404).json({ success: false, message: 'Route not found' });
});

// ========== START ==========
const PORT = process.env.PORT || 3000;
app.listen(PORT, '0.0.0.0', () => {
  console.log(`\n🚀 DRINKQUICK SERVER v3.0 🚀`);
  console.log(`📍 Port: ${PORT}`);
  console.log('🗄️  Database: Supabase PostgreSQL');
  console.log('📧 Email: Password Reset Codes Enabled');
  console.log('✅ Session Management: Enabled');
  console.log('✅ Staff Approval System: Enabled');
  console.log('✅ Approval Logging: Enabled\n');
});
