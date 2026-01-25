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
      SELECT id, username, email, role, created_at 
      FROM users 
      ORDER BY created_at DESC
    `);
    
    const users = result.rows.map(user => ({
      _id: user.id,
      name: user.username,
      email: user.email,
      role: user.role,
      createdAt: user.created_at,
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
    
    console.log(`📊 Stats: ${totalUsers} total, ${newToday} new today`);
    
    res.json({
      success: true,
      totalUsers,
      newToday,
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
      'DELETE FROM users WHERE id = $1 RETURNING username, email',
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

// ========== USER REGISTRATION (For Flutter App) ==========
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

// ========== BASIC ROUTES ==========

// Home page
app.get('/', (req, res) => {
  res.json({ 
    success: true, 
    message: 'DrinkQuick API 🍹',
    database: 'PostgreSQL on Render',
    admin: '/admin',
    register: 'POST /api/auth/register'
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

// Admin panel page
app.get('/admin', (req, res) => {
  res.sendFile(path.join(__dirname, 'public', 'admin.html'));
});

// ========== START SERVER ==========
const PORT = process.env.PORT || 3000;
app.listen(PORT, '0.0.0.0', () => {
  console.log('\n🚀🚀🚀 DRINKQUICK SERVER STARTED 🚀🚀🚀');
  console.log(`📍 Port: ${PORT}`);
  console.log(`🌐 URL: https://drink-quick-cal-kja1.onrender.com`);
  console.log(`🔐 Admin: /admin (password: ${ADMIN_PASSWORD})`);
  console.log(`🗄️  Database: PostgreSQL`);
  console.log('========================================\n');
});
