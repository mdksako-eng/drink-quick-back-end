const express = require('express');
const cors = require('cors');
const path = require('path');
const { Pool } = require('pg');
require('dotenv').config();

const app = express();

// ========== POSTGRESQL SETUP ==========
console.log('🔌 Connecting to PostgreSQL...');
const pool = new Pool({
  connectionString: process.env.DATABASE_URL,
  ssl: { rejectUnauthorized: false }
});

// Test connection
pool.query('SELECT NOW()', (err, res) => {
  if (err) {
    console.error('❌ PostgreSQL Connection Failed:', err.message);
  } else {
    console.log('✅ PostgreSQL Connected:', res.rows[0].now);
    
    // Create users table if not exists
    pool.query(`
      CREATE TABLE IF NOT EXISTS users (
        id SERIAL PRIMARY KEY,
        username VARCHAR(50) NOT NULL,
        email VARCHAR(100) UNIQUE NOT NULL,
        password TEXT NOT NULL,
        role VARCHAR(20) DEFAULT 'Customer',
        profile_image TEXT DEFAULT '',
        is_active BOOLEAN DEFAULT TRUE,
        email_verified BOOLEAN DEFAULT FALSE,
        last_login TIMESTAMP,
        created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
        updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
      )
    `).then(() => {
      console.log('✅ Users table ready');
    }).catch(err => {
      console.error('❌ Table error:', err.message);
    });
  }
});

// ========== MIDDLEWARE ==========
app.use(cors());
app.use(express.json());
app.use(express.static('public'));

// ========== ADMIN AUTH ==========
const ADMIN_PASSWORD = process.env.ADMIN_PASSWORD || 'admin123';

const verifyAdmin = (req, res, next) => {
  const authHeader = req.headers.authorization;
  if (!authHeader || !authHeader.startsWith('Bearer ')) {
    return res.status(401).json({ success: false, message: 'No token' });
  }
  
  const token = authHeader.split(' ')[1];
  if (token === ADMIN_PASSWORD) {
    next();
  } else {
    res.status(403).json({ success: false, message: 'Wrong password' });
  }
};

// ========== ADMIN ROUTES ==========

// 1. GET ALL USERS
app.get('/api/admin/users', verifyAdmin, async (req, res) => {
  try {
    console.log('📋 Fetching all users...');
    const result = await pool.query(`
      SELECT id, username, email, role, created_at, last_login, is_active, email_verified
      FROM users 
      ORDER BY created_at DESC
    `);
    
    const users = result.rows.map(user => ({
      _id: user.id,
      name: user.username,
      email: user.email,
      role: user.role,
      createdAt: user.created_at,
      lastLogin: user.last_login,
      isActive: user.is_active,
      emailVerified: user.email_verified,
      isAdmin: user.role === 'Administrator'
    }));
    
    console.log(`✅ Found ${users.length} users`);
    res.json({ success: true, count: users.length, users });
    
  } catch (error) {
    console.error('❌ Error fetching users:', error);
    res.status(500).json({ success: false, message: error.message });
  }
});

// 2. GET STATS
app.get('/api/admin/stats', verifyAdmin, async (req, res) => {
  try {
    console.log('📊 Getting stats...');
    
    // Total users
    const totalResult = await pool.query('SELECT COUNT(*) FROM users');
    const totalUsers = parseInt(totalResult.rows[0].count);
    
    // New today
    const today = new Date();
    today.setHours(0, 0, 0, 0);
    const todayResult = await pool.query(
      'SELECT COUNT(*) FROM users WHERE created_at >= $1',
      [today]
    );
    const newToday = parseInt(todayResult.rows[0].count);
    
    // Active users
    const activeResult = await pool.query('SELECT COUNT(*) FROM users WHERE is_active = true');
    const activeUsers = parseInt(activeResult.rows[0].count);
    
    console.log(`📊 Stats: ${totalUsers} total, ${newToday} new today, ${activeUsers} active`);
    
    res.json({
      success: true,
      totalUsers,
      newToday,
      activeUsers,
      timestamp: new Date().toISOString()
    });
    
  } catch (error) {
    console.error('❌ Stats error:', error);
    res.status(500).json({ success: false, message: error.message });
  }
});

// 3. DELETE USER
app.delete('/api/admin/users/:id', verifyAdmin, async (req, res) => {
  try {
    const userId = req.params.id;
    console.log(`🗑️  Deleting user ${userId}...`);
    
    const result = await pool.query(
      'DELETE FROM users WHERE id = $1 RETURNING username, email, role',
      [userId]
    );
    
    if (result.rowCount === 0) {
      return res.status(404).json({ success: false, message: 'User not found' });
    }
    
    const deletedUser = result.rows[0];
    console.log(`✅ Deleted: ${deletedUser.username} (${deletedUser.email})`);
    
    res.json({
      success: true,
      message: 'User deleted',
      deletedUser
    });
    
  } catch (error) {
    console.error('❌ Delete error:', error);
    res.status(500).json({ success: false, message: error.message });
  }
});

// ========== AUTH ROUTES FOR FLUTTER APP ==========

// 1. REGISTER USER
app.post('/api/auth/register', async (req, res) => {
  try {
    const { username, email, password } = req.body;
    console.log(`👤 New registration: ${username} (${email})`);
    
    if (!username || !email || !password) {
      return res.status(400).json({ 
        success: false, 
        message: 'Need username, email, password' 
      });
    }
    
    // Check if email exists
    const existing = await pool.query(
      'SELECT id FROM users WHERE email = $1',
      [email]
    );
    
    if (existing.rows.length > 0) {
      return res.status(400).json({ 
        success: false, 
        message: 'Email already used' 
      });
    }
    
    // Insert new user
    const result = await pool.query(
      `INSERT INTO users (username, email, password) 
       VALUES ($1, $2, $3) 
       RETURNING id, username, email, role, created_at`,
      [username, email, password]
    );
    
    const newUser = result.rows[0];
    console.log(`✅ Registered: ${newUser.username} (ID: ${newUser.id})`);
    
    res.json({
      success: true,
      message: 'Welcome! Registration successful',
      user: newUser
    });
    
  } catch (error) {
    console.error('❌ Registration error:', error);
    res.status(500).json({ success: false, message: error.message });
  }
});

// 2. LOGIN USER - THIS IS WHAT YOUR FLUTTER APP NEEDS
app.post('/api/auth/login', async (req, res) => {
  try {
    const { email, password } = req.body;
    console.log(`🔑 Login attempt: ${email}`);
    
    if (!email || !password) {
      return res.status(400).json({ 
        success: false, 
        message: 'Email and password required' 
      });
    }
    
    // Find user by email
    const result = await pool.query(
      'SELECT id, username, email, password, role, is_active FROM users WHERE email = $1',
      [email]
    );
    
    if (result.rows.length === 0) {
      return res.status(401).json({ 
        success: false, 
        message: 'Invalid email or password' 
      });
    }
    
    const user = result.rows[0];
    
    // Check if account is active
    if (!user.is_active) {
      return res.status(403).json({ 
        success: false, 
        message: 'Account is deactivated' 
      });
    }
    
    // Check password (plain text for now)
    if (password !== user.password) {
      return res.status(401).json({ 
        success: false, 
        message: 'Invalid email or password' 
      });
    }
    
    // Update last login time
    await pool.query(
      'UPDATE users SET last_login = CURRENT_TIMESTAMP, updated_at = CURRENT_TIMESTAMP WHERE id = $1',
      [user.id]
    );
    
    // Return user data (without password)
    const { password: _, ...userWithoutPassword } = user;
    
    console.log(`✅ Login successful: ${user.username}`);
    
    res.json({
      success: true,
      message: 'Login successful',
      user: userWithoutPassword,
      token: 'dummy-token-for-now' // In production, generate JWT
    });
    
  } catch (error) {
    console.error('❌ Login error:', error);
    res.status(500).json({ 
      success: false, 
      message: 'Login failed: ' + error.message 
    });
  }
});

// 3. GET USER PROFILE
app.get('/api/auth/me', async (req, res) => {
  try {
    const userId = req.query.userId || req.headers['user-id'];
    
    if (!userId) {
      return res.status(400).json({ 
        success: false, 
        message: 'User ID required' 
      });
    }
    
    const result = await pool.query(
      'SELECT id, username, email, role, profile_image, created_at, last_login FROM users WHERE id = $1',
      [userId]
    );
    
    if (result.rows.length === 0) {
      return res.status(404).json({ 
        success: false, 
        message: 'User not found' 
      });
    }
    
    res.json({
      success: true,
      user: result.rows[0]
    });
    
  } catch (error) {
    console.error('❌ Get profile error:', error);
    res.status(500).json({ 
      success: false, 
      message: error.message 
    });
  }
});

// 4. UPDATE USER PROFILE
app.put('/api/auth/update-profile', async (req, res) => {
  try {
    const { userId, username, email, profileImage } = req.body;
    
    if (!userId) {
      return res.status(400).json({ 
        success: false, 
        message: 'User ID required' 
      });
    }
    
    const result = await pool.query(
      `UPDATE users 
       SET username = COALESCE($1, username), 
           email = COALESCE($2, email),
           profile_image = COALESCE($3, profile_image),
           updated_at = CURRENT_TIMESTAMP
       WHERE id = $4 
       RETURNING id, username, email, role, profile_image`,
      [username, email, profileImage, userId]
    );
    
    if (result.rowCount === 0) {
      return res.status(404).json({ 
        success: false, 
        message: 'User not found' 
      });
    }
    
    res.json({
      success: true,
      message: 'Profile updated successfully',
      user: result.rows[0]
    });
    
  } catch (error) {
    console.error('❌ Update profile error:', error);
    res.status(500).json({ 
      success: false, 
      message: error.message 
    });
  }
});

// 5. LOGOUT
app.post('/api/auth/logout', (req, res) => {
  res.json({ 
    success: true, 
    message: 'Logged out successfully' 
  });
});

// 6. CHANGE PASSWORD
app.put('/api/auth/change-password', async (req, res) => {
  try {
    const { userId, currentPassword, newPassword } = req.body;
    
    if (!userId || !currentPassword || !newPassword) {
      return res.status(400).json({ 
        success: false, 
        message: 'All fields required' 
      });
    }
    
    // Get current password
    const result = await pool.query(
      'SELECT password FROM users WHERE id = $1',
      [userId]
    );
    
    if (result.rows.length === 0) {
      return res.status(404).json({ 
        success: false, 
        message: 'User not found' 
      });
    }
    
    const user = result.rows[0];
    
    // Check current password
    if (currentPassword !== user.password) {
      return res.status(401).json({ 
        success: false, 
        message: 'Current password is incorrect' 
      });
    }
    
    // Update password
    await pool.query(
      'UPDATE users SET password = $1, updated_at = CURRENT_TIMESTAMP WHERE id = $2',
      [newPassword, userId]
    );
    
    res.json({
      success: true,
      message: 'Password changed successfully'
    });
    
  } catch (error) {
    console.error('❌ Change password error:', error);
    res.status(500).json({ 
      success: false, 
      message: error.message 
    });
  }
});

// ========== BASIC ROUTES ==========

// Home page
app.get('/', (req, res) => {
  res.json({ 
    success: true, 
    message: 'DrinkQuick API 🍹',
    database: 'PostgreSQL on Render',
    version: '1.0.0',
    endpoints: {
      auth: {
        register: 'POST /api/auth/register',
        login: 'POST /api/auth/login',
        profile: 'GET /api/auth/me',
        logout: 'POST /api/auth/logout',
        update: 'PUT /api/auth/update-profile',
        changePassword: 'PUT /api/auth/change-password'
      },
      admin: {
        users: 'GET /api/admin/users',
        stats: 'GET /api/admin/stats',
        delete: 'DELETE /api/admin/users/:id',
        panel: '/admin'
      }
    }
  });
});

// Health check
app.get('/health', async (req, res) => {
  try {
    await pool.query('SELECT 1');
    res.json({ 
      success: true, 
      status: '✅ ONLINE', 
      database: '✅ CONNECTED',
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

// Debug database
app.get('/debug-db', async (req, res) => {
  try {
    const usersCount = await pool.query('SELECT COUNT(*) FROM users');
    const dbTime = await pool.query('SELECT NOW()');
    res.json({
      success: true,
      users: parseInt(usersCount.rows[0].count),
      databaseTime: dbTime.rows[0].now,
      hasDatabaseUrl: !!process.env.DATABASE_URL
    });
  } catch (error) {
    res.json({ success: false, error: error.message });
  }
});

// Admin panel page
app.get('/admin', (req, res) => {
  res.sendFile(path.join(__dirname, 'public', 'admin.html'));
});

// ========== ERROR HANDLING ==========
app.use((req, res) => {
  res.status(404).json({
    success: false,
    message: 'Route not found',
    available: [
      '/',
      '/health',
      '/admin',
      '/api/auth/register',
      '/api/auth/login',
      '/api/auth/me',
      '/api/auth/logout'
    ]
  });
});

// ========== START SERVER ==========
const PORT = process.env.PORT || 3000;
app.listen(PORT, '0.0.0.0', () => {
  console.log('\n🚀🚀🚀 DRINKQUICK SERVER STARTED 🚀🚀🚀');
  console.log(`📍 Port: ${PORT}`);
  console.log(`🌐 URL: https://drink-quick-cal-kja1.onrender.com`);
  console.log(`🔐 Admin: /admin (password: ${ADMIN_PASSWORD})`);
  console.log(`🔑 Login: POST /api/auth/login`);
  console.log(`👤 Register: POST /api/auth/register`);
  console.log(`🗄️  Database: PostgreSQL`);
  console.log('========================================\n');
});
