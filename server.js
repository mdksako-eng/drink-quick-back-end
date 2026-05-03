const express = require('express');
const cors = require('cors');
const path = require('path');
const { Pool } = require('pg');
require('dotenv').config();

const app = express();

// ========== POSTGRESQL SETUP ==========
console.log('🔌 Connecting to PostgreSQL (Neon)...');
console.log('✅ Migration Status: COMPLETE - Using Neon PostgreSQL');

const pool = new Pool({
  connectionString: process.env.DATABASE_URL,
  ssl: { 
    rejectUnauthorized: false 
  },
  connectionTimeoutMillis: 10000,
  idleTimeoutMillis: 30000,
  max: 20
});

// Test connection and setup table
(async () => {
  try {
    await pool.query('SELECT NOW()');
    console.log('✅ PostgreSQL Connected (Neon)');
    
    // Create users table if not exists
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

    // Create companies table if not exists
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

    // Add foreign key if not exists
    await pool.query(`
      DO $$
      BEGIN
        IF NOT EXISTS (
          SELECT 1 FROM information_schema.table_constraints 
          WHERE constraint_name = 'fk_users_company'
        ) THEN
          ALTER TABLE users 
          ADD CONSTRAINT fk_users_company 
          FOREIGN KEY (company_id) 
          REFERENCES companies(id);
        END IF;
      END $$;
    `);
    console.log('✅ Foreign key ready');

    // Insert default company if not exists
    await pool.query(`
      INSERT INTO companies (name, code) 
      VALUES ('My Business', 'MYBIZ')
      ON CONFLICT (code) DO NOTHING
    `);
    
    const countResult = await pool.query('SELECT COUNT(*) FROM users');
    const userCount = parseInt(countResult.rows[0].count);
    console.log(`📊 Database has ${userCount} users`);
    
  } catch (error) {
    console.error('❌ Database setup error:', error.message);
    console.error('🔧 Hint: Check DATABASE_URL environment variable');
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

// Verify user token (for regular users)
const verifyUser = async (req, res, next) => {
  const userId = req.headers['user-id'] || req.query.userId;
  if (!userId) {
    return res.status(401).json({ success: false, message: 'User ID required' });
  }
  
  try {
    const result = await pool.query('SELECT id, role, is_active FROM users WHERE id = $1', [userId]);
    if (result.rows.length === 0) {
      return res.status(401).json({ success: false, message: 'User not found' });
    }
    
    if (!result.rows[0].is_active) {
      return res.status(403).json({ success: false, message: 'Account is deactivated' });
    }
    
    req.currentUser = result.rows[0];
    next();
  } catch (error) {
    res.status(500).json({ success: false, message: error.message });
  }
};

// ========== AUTH ROUTES ==========

// 1. REGISTER USER
app.post('/api/auth/register', async (req, res) => {
  try {
    const { username, email, password, securityQuestions } = req.body;
    console.log(`👤 New registration: ${username} (${email})`);
    
    if (!username || !email || !password) {
      return res.status(400).json({ 
        status: 'error', 
        message: 'Username, email, and password are required' 
      });
    }
    
    // Check if email exists
    const existingEmail = await pool.query('SELECT id FROM users WHERE email = $1', [email]);
    if (existingEmail.rows.length > 0) {
      return res.status(400).json({ status: 'error', message: 'Email already registered' });
    }
    
    // Check if username exists
    const existingUsername = await pool.query('SELECT id FROM users WHERE username = $1', [username]);
    if (existingUsername.rows.length > 0) {
      return res.status(400).json({ status: 'error', message: 'Username already taken' });
    }
    
    // Insert new user
    const result = await pool.query(
      `INSERT INTO users (username, email, password, role, security_question1, security_question2) 
       VALUES ($1, $2, $3, 'Customer', $4, $5) 
       RETURNING id, username, email, role, company_id, is_active, created_at`,
      [
        username, 
        email, 
        password, 
        securityQuestions?.question1 || securityQuestions?.answer1 || '',
        securityQuestions?.question2 || securityQuestions?.answer2 || ''
      ]
    );
    
    const newUser = result.rows[0];
    console.log(`✅ Registered: ${newUser.username} (ID: ${newUser.id})`);
    
    res.status(201).json({
      status: 'success',
      message: 'Registration successful',
      data: {
        user: {
          id: newUser.id,
          _id: newUser.id,
          username: newUser.username,
          email: newUser.email,
          role: newUser.role,
          companyId: newUser.company_id,
          isActive: newUser.is_active
        },
        token: 'token_' + newUser.id
      }
    });
    
  } catch (error) {
    console.error('❌ Registration error:', error.message);
    res.status(500).json({ status: 'error', message: error.message });
  }
});

// 2. LOGIN USER
app.post('/api/auth/login', async (req, res) => {
  try {
    const { username, email, password } = req.body;
    console.log(`🔑 Login attempt: ${email || username}`);
    
    if (!password || (!email && !username)) {
      return res.status(400).json({ 
        status: 'error', 
        message: 'Email/username and password required' 
      });
    }
    
    let result;
    
    if (email) {
      result = await pool.query(
        'SELECT id, username, email, password, role, company_id, is_active FROM users WHERE email = $1',
        [email]
      );
    } else {
      result = await pool.query(
        'SELECT id, username, email, password, role, company_id, is_active FROM users WHERE username = $1',
        [username]
      );
    }
    
    if (result.rows.length === 0) {
      return res.status(401).json({ status: 'error', message: 'Invalid credentials' });
    }
    
    const user = result.rows[0];
    
    if (user.is_active === false) {
      return res.status(403).json({ status: 'error', message: 'Account is deactivated. Contact your manager.' });
    }
    
    if (password !== user.password) {
      return res.status(401).json({ status: 'error', message: 'Invalid credentials' });
    }
    
    // Update last login
    await pool.query(
      'UPDATE users SET last_login = CURRENT_TIMESTAMP, updated_at = CURRENT_TIMESTAMP WHERE id = $1',
      [user.id]
    );
    
    const { password: _, ...userWithoutPassword } = user;
    
    console.log(`✅ Login successful: ${user.username} (${user.role})`);
    
    res.json({
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
          isActive: user.is_active
        },
        token: 'token_' + user.id
      }
    });
    
  } catch (error) {
    console.error('❌ Login error:', error.message);
    res.status(500).json({ status: 'error', message: 'Login failed' });
  }
});

// 3. GET USER PROFILE
app.get('/api/auth/me', async (req, res) => {
  try {
    const userId = req.headers['user-id'] || req.query.userId;
    
    if (!userId) {
      return res.status(400).json({ status: 'error', message: 'User ID required' });
    }
    
    const result = await pool.query(
      `SELECT id, username, email, role, company_id, profile_image, is_active, 
              email_verified, last_login, created_at, updated_at 
       FROM users WHERE id = $1`,
      [userId]
    );
    
    if (result.rows.length === 0) {
      return res.status(404).json({ status: 'error', message: 'User not found' });
    }
    
    const user = result.rows[0];
    
    res.json({
      status: 'success',
      data: {
        user: {
          id: user.id,
          _id: user.id,
          username: user.username,
          email: user.email,
          role: user.role,
          companyId: user.company_id,
          profileImage: user.profile_image,
          isActive: user.is_active,
          emailVerified: user.email_verified,
          lastLogin: user.last_login,
          createdAt: user.created_at
        }
      }
    });
    
  } catch (error) {
    console.error('❌ Get profile error:', error.message);
    res.status(500).json({ status: 'error', message: error.message });
  }
});

// 4. LOGOUT
app.post('/api/auth/logout', (req, res) => {
  res.json({ status: 'success', message: 'Logged out successfully' });
});

// ========== USER MANAGEMENT ROUTES ==========

// CREATE STAFF (Admin & Manager)
app.post('/api/auth/create-staff', async (req, res) => {
  try {
    const { username, email, password, securityQuestions } = req.body;
    const creatorId = req.headers['user-id'];
    
    console.log(`👤 Creating staff: ${username} (by user ${creatorId})`);
    
    // Check if user exists
    const existing = await pool.query(
      'SELECT id FROM users WHERE username = $1 OR email = $2',
      [username, email]
    );
    
    if (existing.rows.length > 0) {
      return res.status(400).json({ status: 'error', message: 'Username or email already exists' });
    }
    
    // Get creator's company_id
    let companyId = null;
    if (creatorId) {
      const creator = await pool.query('SELECT company_id, role FROM users WHERE id = $1', [creatorId]);
      if (creator.rows.length > 0) {
        companyId = creator.rows[0].company_id;
      }
    }
    
    // Insert staff
    const result = await pool.query(
      `INSERT INTO users (username, email, password, role, company_id, security_question1, security_question2) 
       VALUES ($1, $2, $3, 'Staff', $4, $5, $6) 
       RETURNING id, username, email, role, company_id, is_active, created_at`,
      [
        username, 
        email, 
        password, 
        companyId,
        securityQuestions?.question1 || '',
        securityQuestions?.question2 || ''
      ]
    );
    
    console.log(`✅ Staff created: ${username} (Company: ${companyId})`);
    
    res.status(201).json({
      status: 'success',
      message: 'Staff account created successfully',
      data: {
        user: {
          id: result.rows[0].id,
          _id: result.rows[0].id,
          username: result.rows[0].username,
          email: result.rows[0].email,
          role: result.rows[0].role,
          companyId: result.rows[0].company_id,
          isActive: result.rows[0].is_active
        },
        createdBy: creatorId
      }
    });
    
  } catch (error) {
    console.error('❌ Create staff error:', error.message);
    res.status(500).json({ status: 'error', message: error.message });
  }
});

// BLOCK USER (Admin & Manager)
app.post('/api/auth/block-user/:id', async (req, res) => {
  try {
    const userId = req.params.id;
    const requesterId = req.headers['user-id'];
    
    console.log(`🚫 Blocking user ${userId} (requested by ${requesterId})`);
    
    // Check if user exists
    const userResult = await pool.query('SELECT id, username, email, role, company_id, is_active FROM users WHERE id = $1', [userId]);
    
    if (userResult.rowCount === 0) {
      return res.status(404).json({ status: 'error', message: 'User not found' });
    }
    
    const user = userResult.rows[0];
    
    // Prevent blocking yourself
    if (requesterId && parseInt(requesterId) === user.id) {
      return res.status(400).json({ status: 'error', message: 'Cannot block your own account' });
    }
    
    // Prevent blocking Administrator
    if (user.role === 'Administrator') {
      return res.status(403).json({ status: 'error', message: 'Cannot block an Administrator' });
    }
    
    // Block user
    const result = await pool.query(
      'UPDATE users SET is_active = false, updated_at = CURRENT_TIMESTAMP WHERE id = $1 RETURNING id, username, email, role, is_active',
      [userId]
    );
    
    console.log(`✅ Blocked: ${result.rows[0].username}`);
    
    res.json({
      status: 'success',
      message: `${result.rows[0].username} has been blocked`,
      data: {
        user: {
          id: result.rows[0].id,
          username: result.rows[0].username,
          role: result.rows[0].role,
          isActive: false
        }
      }
    });
    
  } catch (error) {
    console.error('❌ Block error:', error.message);
    res.status(500).json({ status: 'error', message: error.message });
  }
});

// UNBLOCK USER (Admin & Manager)
app.post('/api/auth/unblock-user/:id', async (req, res) => {
  try {
    const userId = req.params.id;
    
    console.log(`✅ Unblocking user ${userId}`);
    
    const userResult = await pool.query('SELECT id, username, email, role FROM users WHERE id = $1', [userId]);
    
    if (userResult.rowCount === 0) {
      return res.status(404).json({ status: 'error', message: 'User not found' });
    }
    
    const result = await pool.query(
      'UPDATE users SET is_active = true, updated_at = CURRENT_TIMESTAMP WHERE id = $1 RETURNING id, username, email, role, is_active',
      [userId]
    );
    
    console.log(`✅ Unblocked: ${result.rows[0].username}`);
    
    res.json({
      status: 'success',
      message: `${result.rows[0].username} has been unblocked`,
      data: {
        user: {
          id: result.rows[0].id,
          username: result.rows[0].username,
          role: result.rows[0].role,
          isActive: true
        }
      }
    });
    
  } catch (error) {
    console.error('❌ Unblock error:', error.message);
    res.status(500).json({ status: 'error', message: error.message });
  }
});

// DELETE USER (Admin only)
app.delete('/api/auth/users/:id', verifyAdmin, async (req, res) => {
  try {
    const userId = req.params.id;
    console.log(`🗑️ Deleting user ${userId}`);
    
    const userResult = await pool.query('SELECT id, username, email, role FROM users WHERE id = $1', [userId]);
    
    if (userResult.rowCount === 0) {
      return res.status(404).json({ status: 'error', message: 'User not found' });
    }
    
    const user = userResult.rows[0];
    
    if (user.role === 'Administrator') {
      return res.status(403).json({ status: 'error', message: 'Cannot delete an Administrator' });
    }
    
    await pool.query('DELETE FROM users WHERE id = $1', [userId]);
    
    console.log(`✅ Deleted: ${user.username}`);
    
    res.json({
      status: 'success',
      message: `${user.username} has been permanently deleted`,
      data: {
        deletedUser: { id: user.id, username: user.username, role: user.role }
      }
    });
    
  } catch (error) {
    console.error('❌ Delete error:', error.message);
    res.status(500).json({ status: 'error', message: error.message });
  }
});

// GET USERS (with optional role filter)
app.get('/api/users', async (req, res) => {
  try {
    const { role, search } = req.query;
    let query = `SELECT id, username, email, role, company_id, is_active, created_at, last_login FROM users WHERE 1=1`;
    const params = [];
    let paramCount = 1;
    
    if (role) {
      query += ` AND role = $${paramCount}`;
      params.push(role);
      paramCount++;
    }
    
    if (search) {
      query += ` AND (username ILIKE $${paramCount} OR email ILIKE $${paramCount})`;
      params.push(`%${search}%`);
      paramCount++;
    }
    
    query += ` ORDER BY created_at DESC`;
    
    const result = await pool.query(query, params);
    
    const users = result.rows.map(u => ({
      _id: u.id,
      id: u.id,
      username: u.username,
      email: u.email,
      role: u.role,
      companyId: u.company_id,
      isActive: u.is_active,
      createdAt: u.created_at,
      lastLogin: u.last_login
    }));
    
    res.json({
      status: 'success',
      data: { users }
    });
    
  } catch (error) {
    console.error('❌ Get users error:', error.message);
    res.status(500).json({ status: 'error', message: error.message });
  }
});

// UPDATE USER (Admin)
app.put('/api/users/:id', verifyAdmin, async (req, res) => {
  try {
    const { id } = req.params;
    const { role, company_id } = req.body;
    
    const result = await pool.query(
      'UPDATE users SET role = COALESCE($1, role), company_id = $2, updated_at = CURRENT_TIMESTAMP WHERE id = $3 RETURNING id, username, email, role, company_id, is_active',
      [role, company_id, id]
    );
    
    if (result.rowCount === 0) {
      return res.status(404).json({ status: 'error', message: 'User not found' });
    }
    
    res.json({ status: 'success', message: 'User updated', data: { user: result.rows[0] } });
    
  } catch (error) {
    res.status(500).json({ status: 'error', message: error.message });
  }
});

// ========== ADMIN ROUTES ==========

// GET ALL USERS (Admin)
app.get('/api/admin/users', verifyAdmin, async (req, res) => {
  try {
    console.log('📋 Admin fetching all users...');
    
    const result = await pool.query(`
      SELECT id, username, email, role, company_id, created_at, updated_at, 
             last_login, is_active, email_verified, profile_image
      FROM users 
      ORDER BY created_at DESC
    `);
    
    const users = result.rows.map(user => ({
      _id: user.id,
      id: user.id,
      name: user.username,
      username: user.username,
      email: user.email,
      role: user.role,
      companyId: user.company_id,
      createdAt: user.created_at,
      updatedAt: user.updated_at,
      lastLogin: user.last_login,
      isActive: user.is_active,
      emailVerified: user.email_verified,
      profileImage: user.profile_image,
      isAdmin: user.role === 'Administrator'
    }));
    
    console.log(`✅ Found ${users.length} users`);
    res.json({ success: true, count: users.length, users, status: 'success', data: { users } });
    
  } catch (error) {
    console.error('❌ Error fetching users:', error.message);
    res.status(500).json({ success: false, message: error.message });
  }
});

// GET STATS (Admin)
app.get('/api/admin/stats', verifyAdmin, async (req, res) => {
  try {
    const totalResult = await pool.query('SELECT COUNT(*) FROM users');
    const totalUsers = parseInt(totalResult.rows[0].count);
    
    const today = new Date();
    today.setHours(0, 0, 0, 0);
    const todayResult = await pool.query('SELECT COUNT(*) FROM users WHERE created_at >= $1', [today]);
    const newToday = parseInt(todayResult.rows[0].count);
    
    const activeResult = await pool.query('SELECT COUNT(*) FROM users WHERE is_active = true');
    const activeUsers = parseInt(activeResult.rows[0].count);
    
    res.json({
      success: true,
      totalUsers,
      newToday,
      activeUsers,
      timestamp: new Date().toISOString()
    });
    
  } catch (error) {
    console.error('❌ Stats error:', error.message);
    res.status(500).json({ success: false, message: error.message });
  }
});

// DELETE USER (Admin)
app.delete('/api/admin/users/:id', verifyAdmin, async (req, res) => {
  try {
    const userId = req.params.id;
    console.log(`🗑️ Admin deleting user ${userId}`);
    
    const result = await pool.query(
      'DELETE FROM users WHERE id = $1 RETURNING username, email, role',
      [userId]
    );
    
    if (result.rowCount === 0) {
      return res.status(404).json({ success: false, message: 'User not found' });
    }
    
    console.log(`✅ Deleted: ${result.rows[0].username}`);
    res.json({ success: true, message: 'User deleted', deletedUser: result.rows[0] });
    
  } catch (error) {
    console.error('❌ Delete error:', error.message);
    res.status(500).json({ success: false, message: error.message });
  }
});

// ========== OTHER ROUTES ==========

app.get('/api/drinks', (req, res) => {
  res.json({
    success: true,
    count: 4,
    drinks: [
      { id: 1, name: 'Mojito', category: 'Cocktail', price: 8.99 },
      { id: 2, name: 'Margarita', category: 'Cocktail', price: 9.99 },
      { id: 3, name: 'Beer', category: 'Beer', price: 5.99 },
      { id: 4, name: 'Wine', category: 'Wine', price: 7.99 }
    ]
  });
});

app.get('/api/test', (req, res) => {
  res.json({
    success: true,
    message: 'DrinkQuick API v2.0',
    working: true,
    timestamp: new Date().toISOString(),
    database: 'Neon PostgreSQL',
    endpoints: [
      'POST /api/auth/register',
      'POST /api/auth/login',
      'GET /api/auth/me',
      'POST /api/auth/logout',
      'POST /api/auth/create-staff',
      'POST /api/auth/block-user/:id',
      'POST /api/auth/unblock-user/:id',
      'DELETE /api/auth/users/:id',
      'GET /api/users',
      'PUT /api/users/:id',
      'GET /api/admin/users',
      'GET /api/admin/stats',
      'DELETE /api/admin/users/:id'
    ]
  });
});

app.get('/api/ping', (req, res) => {
  res.json({ success: true, message: 'pong', timestamp: Date.now() });
});

// ========== BASIC ROUTES ==========

app.get('/', (req, res) => {
  res.json({ 
    success: true, 
    message: 'DrinkQuick API 🍹',
    version: '2.0',
    status: '🟢 ONLINE',
    database: 'Neon PostgreSQL'
  });
});

app.get('/health', async (req, res) => {
  try {
    await pool.query('SELECT NOW()');
    const usersCount = await pool.query('SELECT COUNT(*) FROM users');
    
    res.json({ 
      success: true, 
      status: '✅ ONLINE', 
      database: '✅ CONNECTED (Neon)',
      users: parseInt(usersCount.rows[0].count),
      time: new Date().toISOString()
    });
  } catch (error) {
    res.json({ 
      success: true, 
      status: '⚠️ ONLINE', 
      database: '❌ DISCONNECTED',
      error: error.message
    });
  }
});

app.get('/debug-db', async (req, res) => {
  try {
    const usersCount = await pool.query('SELECT COUNT(*) FROM users');
    const columnsResult = await pool.query(`
      SELECT column_name, data_type, is_nullable
      FROM information_schema.columns 
      WHERE table_name = 'users' AND table_schema = 'public'
      ORDER BY ordinal_position
    `);
    
    res.json({
      success: true,
      users: { total: parseInt(usersCount.rows[0].count) },
      columns: columnsResult.rows
    });
  } catch (error) {
    res.json({ success: false, error: error.message });
  }
});

app.get('/admin', (req, res) => {
  res.sendFile(path.join(__dirname, 'public', 'admin.html'));
});

// ========== ERROR HANDLING ==========
app.use((req, res) => {
  res.status(404).json({
    success: false,
    message: 'Route not found',
    available: [
      '/', '/health', '/admin', '/debug-db',
      '/api/auth/register', '/api/auth/login', '/api/auth/me', '/api/auth/logout',
      '/api/auth/create-staff', '/api/auth/block-user/:id', '/api/auth/unblock-user/:id',
      '/api/auth/users/:id', '/api/users', '/api/users/:id',
      '/api/admin/users', '/api/admin/stats', '/api/admin/users/:id',
      '/api/test', '/api/drinks', '/api/ping'
    ]
  });
});

// ========== START SERVER ==========
const PORT = process.env.PORT || 3000;
app.listen(PORT, '0.0.0.0', () => {
  console.log('\n🚀 DRINKQUICK SERVER v2.0 🚀');
  console.log('📍 Port:', PORT);
  console.log('🗄️  Database: Neon PostgreSQL');
  console.log('\n🔑 AUTH ENDPOINTS:');
  console.log('   👤 POST /api/auth/register');
  console.log('   🔑 POST /api/auth/login');
  console.log('   👁️  GET /api/auth/me');
  console.log('   🚪 POST /api/auth/logout');
  console.log('   👥 POST /api/auth/create-staff');
  console.log('   🚫 POST /api/auth/block-user/:id');
  console.log('   ✅ POST /api/auth/unblock-user/:id');
  console.log('   🗑️  DELETE /api/auth/users/:id');
  console.log('\n👑 ADMIN ENDPOINTS:');
  console.log('   📋 GET /api/admin/users');
  console.log('   📊 GET /api/admin/stats');
  console.log('   🗑️  DELETE /api/admin/users/:id');
  console.log('\n📊 USER ENDPOINTS:');
  console.log('   📋 GET /api/users');
  console.log('   ✏️  PUT /api/users/:id');
  console.log('\n========================================\n');
});
