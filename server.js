const express = require('express');
const cors = require('cors');
const path = require('path');
const { Pool } = require('pg');
require('dotenv').config();

const app = express();

// ========== POSTGRESQL SETUP ==========
console.log('🔌 Connecting to PostgreSQL...');
console.log('📝 Database URL exists:', !!process.env.DATABASE_URL);
console.log('🔍 Database URL starts with:', process.env.DATABASE_URL ? process.env.DATABASE_URL.substring(0, 20) + '...' : 'Not set');

const pool = new Pool({
  connectionString: process.env.DATABASE_URL,
  ssl: { 
    rejectUnauthorized: false 
  },
  // Neon-specific optimizations
  connectionTimeoutMillis: 10000, // 10 seconds
  idleTimeoutMillis: 30000,
  max: 20
});

// Test connection and setup table
(async () => {
  try {
    await pool.query('SELECT NOW()');
    console.log('✅ PostgreSQL Connected');
    
    // Create users table if not exists (Neon compatible)
    await pool.query(`
      CREATE TABLE IF NOT EXISTS users (
        id SERIAL PRIMARY KEY,
        username VARCHAR(50) NOT NULL,
        email VARCHAR(100) UNIQUE NOT NULL,
        password TEXT NOT NULL,
        role VARCHAR(20) DEFAULT 'Customer',
        created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
        updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
        profile_image TEXT DEFAULT '',
        is_active BOOLEAN DEFAULT TRUE,
        email_verified BOOLEAN DEFAULT FALSE,
        last_login TIMESTAMP
      )
    `);
    console.log('✅ Users table ready');
    
    // Check for existing data
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
    return res.status(401).json({ success: false, message: 'No token' });
  }
  
  const token = authHeader.split(' ')[1];
  if (token === ADMIN_PASSWORD) {
    next();
  } else {
    res.status(403).json({ success: false, message: 'Wrong password' });
  }
};

// ========== MIGRATION BACKUP ROUTE ==========

    
    // Get table structure
    const columnsResult = await pool.query(`
      SELECT column_name, data_type, is_nullable, column_default
      FROM information_schema.columns 
      WHERE table_name = 'users' AND table_schema = 'public'
      ORDER BY ordinal_position
    `);
    
    const userCount = usersResult.rows.length;
    console.log(`✅ Found ${userCount} users to backup`);
    
    // Generate SQL for Neon import
    let sqlImport = `-- DrinkQuick Migration to Neon SQL
-- Generated: ${new Date().toISOString()}
-- Total users: ${userCount}

-- Drop table if exists (for clean import)
DROP TABLE IF EXISTS users CASCADE;

-- Create users table with all columns
CREATE TABLE users (
  id SERIAL PRIMARY KEY,
  username VARCHAR(50) NOT NULL,
  email VARCHAR(100) UNIQUE NOT NULL,
  password TEXT NOT NULL,
  role VARCHAR(20) DEFAULT 'Customer',
  created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
  updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
  profile_image TEXT DEFAULT '',
  is_active BOOLEAN DEFAULT TRUE,
  email_verified BOOLEAN DEFAULT FALSE,
  last_login TIMESTAMP
);

-- Insert user data
`;
    
    // Add INSERT statements for each user
    usersResult.rows.forEach((user) => {
      // Escape single quotes in strings
      const safeUsername = user.username.replace(/'/g, "''");
      const safeEmail = user.email.replace(/'/g, "''");
      const safePassword = user.password.replace(/'/g, "''");
      const safeProfileImage = user.profile_image.replace(/'/g, "''");
      
      sqlImport += `INSERT INTO users (id, username, email, password, role, created_at, updated_at, profile_image, is_active, email_verified, last_login) VALUES (
  ${user.id},
  '${safeUsername}',
  '${safeEmail}',
  '${safePassword}',
  '${user.role || 'Customer'}',
  '${user.created_at}',
  '${user.updated_at || user.created_at}',
  '${safeProfileImage}',
  ${user.is_active},
  ${user.email_verified},
  ${user.last_login ? `'${user.last_login}'` : 'NULL'}
);\n`;
    });
    
    sqlImport += `\n-- Reset sequence for future inserts
SELECT setval('users_id_seq', (SELECT MAX(id) FROM users));`;

    res.json({
      success: true,
      timestamp: new Date().toISOString(),
      table_structure: columnsResult.rows,
      users: usersResult.rows,
      total_users: userCount,
      sql_import: sqlImport,
      migration_instructions: `
        ============================================
        🚀 DRINKQUICK MIGRATION TO NEON INSTRUCTIONS
        ============================================
        
        1. CREATE NEON ACCOUNT:
           - Go to https://neon.tech
           - Sign up with GitHub
           - Create project: drinkquick-migrated
           - Region: US East (N. Virginia)
           
        2. IMPORT DATA:
           - Copy the 'sql_import' content above
           - Go to Neon SQL Editor
           - Paste and run ALL SQL commands
           
        3. UPDATE RENDER:
           - Get Neon connection string
           - Add ?pgbouncer=true&sslmode=require
           - Update Render DATABASE_URL environment variable
           
        4. VERIFY:
           - Check /health endpoint
           - Check /api/verify-migration
           
        5. REMOVE THIS BACKUP ROUTE after migration!
        ============================================
      `
    });
    
  } catch (error) {
    console.error('❌ Backup error:', error.message);
    res.status(500).json({ 
      success: false, 
      error: error.message,
      hint: 'Make sure users table exists. If not, your app will create it automatically on first use.'
    });
  }
});

// ========== MIGRATION VERIFICATION ROUTE ==========
app.get('/api/verify-migration', async (req, res) => {
  try {
    // Check database connection
    await pool.query('SELECT NOW()');
    
    // Get database info
    const dbInfo = await pool.query(`
      SELECT 
        current_database() as db_name,
        version() as db_version,
        inet_server_addr() as db_host,
        inet_server_port() as db_port
    `);
    
    // Get user stats
    const usersCount = await pool.query('SELECT COUNT(*) FROM users');
    const recentUsers = await pool.query(
      'SELECT id, username, email, created_at FROM users ORDER BY created_at DESC LIMIT 5'
    );
    
    // Check if we're connected to Neon
    const isNeon = process.env.DATABASE_URL && process.env.DATABASE_URL.includes('neon.tech');
    
    res.json({
      success: true,
      migration_status: isNeon ? '✅ MIGRATED TO NEON' : '⚠️ STILL ON RENDER POSTGRES',
      timestamp: new Date().toISOString(),
      database: {
        name: dbInfo.rows[0].db_name,
        version: dbInfo.rows[0].db_version,
        host: dbInfo.rows[0].db_host,
        port: dbInfo.rows[0].db_port,
        provider: isNeon ? 'Neon' : 'Render'
      },
      users: {
        total: parseInt(usersCount.rows[0].count),
        recent: recentUsers.rows
      },
      connection_string_preview: process.env.DATABASE_URL 
        ? process.env.DATABASE_URL.substring(0, 50) + '...' 
        : 'Not set',
      instructions: isNeon 
        ? 'Migration complete! You can remove /api/backup-data route.'
        : 'Visit /api/backup-data to get migration SQL for Neon.'
    });
    
  } catch (error) {
    res.status(500).json({
      success: false,
      error: error.message,
      message: 'Database connection failed'
    });
  }
});

// ========== ADMIN ROUTES ==========

// 1. GET ALL USERS
app.get('/api/admin/users', verifyAdmin, async (req, res) => {
  try {
    console.log('📋 Fetching all users...');
    
    const result = await pool.query(`
      SELECT 
        id, 
        username, 
        email, 
        role, 
        created_at,
        updated_at,
        COALESCE(last_login, created_at) as last_login,
        COALESCE(is_active, true) as is_active,
        COALESCE(email_verified, false) as email_verified,
        COALESCE(profile_image, '') as profile_image
      FROM users 
      ORDER BY created_at DESC
    `);
    
    const users = result.rows.map(user => ({
      _id: user.id,
      name: user.username,
      email: user.email,
      role: user.role,
      createdAt: user.created_at,
      updatedAt: user.updated_at,
      lastLogin: user.last_login,
      isActive: user.is_active,
      emailVerified: user.email_verified,
      profileImage: user.profile_image,
      isAdmin: user.role === 'Administrator'
    }));
    
    console.log(`✅ Found ${users.length} users`);
    res.json({ success: true, count: users.length, users });
    
  } catch (error) {
    console.error('❌ Error fetching users:', error.message);
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
    
    // Verified users
    const verifiedResult = await pool.query('SELECT COUNT(*) FROM users WHERE email_verified = true');
    const verifiedUsers = parseInt(verifiedResult.rows[0].count);
    
    console.log(`📊 Stats: ${totalUsers} total, ${newToday} new today, ${activeUsers} active, ${verifiedUsers} verified`);
    
    res.json({
      success: true,
      totalUsers,
      newToday,
      activeUsers,
      verifiedUsers,
      timestamp: new Date().toISOString()
    });
    
  } catch (error) {
    console.error('❌ Stats error:', error.message);
    res.status(500).json({ 
      success: false, 
      message: 'Server error',
      error: error.message
    });
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
    console.error('❌ Delete error:', error.message);
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
    
    // Check if username exists
    const existingUsername = await pool.query(
      'SELECT id FROM users WHERE username = $1',
      [username]
    );
    
    if (existingUsername.rows.length > 0) {
      return res.status(400).json({ 
        success: false, 
        message: 'Username already taken' 
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
    console.error('❌ Registration error:', error.message);
    res.status(500).json({ success: false, message: error.message });
  }
});

// 2. LOGIN USER
app.post('/api/auth/login', async (req, res) => {
  try {
    const { username, email, password } = req.body;
    console.log(`🔑 Login attempt: ${email || username}`);
    
    // Check if we have required fields
    if (!password || (!email && !username)) {
      return res.status(400).json({ 
        success: false, 
        message: 'Email/username and password required' 
      });
    }
    
    let result;
    let queryField = '';
    
    // Find user by email OR username
    if (email) {
      queryField = 'email';
      result = await pool.query(
        'SELECT id, username, email, password, role, is_active FROM users WHERE email = $1',
        [email]
      );
    } else {
      queryField = 'username';
      result = await pool.query(
        'SELECT id, username, email, password, role, is_active FROM users WHERE username = $1',
        [username]
      );
    }
    
    console.log(`🔍 Searching by ${queryField}: ${email || username}`);
    
    if (result.rows.length === 0) {
      return res.status(401).json({ 
        success: false, 
        message: 'Invalid email/username or password' 
      });
    }
    
    const user = result.rows[0];
    
    // Check if user is active
    if (user.is_active === false) {
      return res.status(403).json({ 
        success: false, 
        message: 'Account is deactivated' 
      });
    }
    
    // Check password (plain text for now)
    if (password !== user.password) {
      return res.status(401).json({ 
        success: false, 
        message: 'Invalid email/username or password' 
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
      user: userWithoutPassword
    });
    
  } catch (error) {
    console.error('❌ Login error:', error.message);
    res.status(500).json({ 
      success: false, 
      message: 'Login failed',
      error: error.message
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
      `SELECT id, username, email, role, created_at, updated_at, 
              profile_image, is_active, email_verified, last_login 
       FROM users WHERE id = $1`,
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
    console.error('❌ Get profile error:', error.message);
    res.status(500).json({ 
      success: false, 
      message: error.message 
    });
  }
});

// 4. LOGOUT
app.post('/api/auth/logout', (req, res) => {
  res.json({ 
    success: true, 
    message: 'Logged out successfully' 
  });
});

// ========== ADD MISSING ROUTES FOR FLUTTER APP ==========

// 1. /api/test endpoint
app.get('/api/test', (req, res) => {
  res.json({
    success: true,
    message: 'DrinkQuick API v2.0',
    working: true,
    timestamp: new Date().toISOString(),
    migration_ready: true,
    availableEndpoints: [
      'POST /api/auth/register',
      'POST /api/auth/login',
      'GET /api/auth/me',
      'POST /api/auth/logout',
      'GET /api/drinks',
      'GET /api/backup-data (MIGRATION)',
      'GET /api/verify-migration (MIGRATION)',
      '/health',
      '/admin',
      '/debug-db'
    ]
  });
});

// 2. /api/drinks endpoint
app.get('/api/drinks', (req, res) => {
  res.json({
    success: true,
    count: 4,
    drinks: [
      { 
        id: 1, 
        name: 'Mojito', 
        category: 'Cocktail', 
        price: 8.99,
        ingredients: ['Rum', 'Mint', 'Lime', 'Sugar', 'Soda'],
        popular: true
      },
      { 
        id: 2, 
        name: 'Margarita', 
        category: 'Cocktail', 
        price: 9.99,
        ingredients: ['Tequila', 'Triple Sec', 'Lime Juice'],
        popular: true
      },
      { 
        id: 3, 
        name: 'Beer', 
        category: 'Beer', 
        price: 5.99,
        ingredients: ['Barley', 'Hops', 'Water', 'Yeast'],
        popular: true
      },
      { 
        id: 4, 
        name: 'Wine', 
        category: 'Wine', 
        price: 7.99,
        ingredients: ['Grapes', 'Yeast'],
        popular: false
      }
    ],
    timestamp: new Date().toISOString()
  });
});

// 3. Quick ping endpoint to wake up server
app.get('/api/ping', (req, res) => {
  res.json({ 
    success: true, 
    message: 'pong',
    timestamp: Date.now(),
    server: 'DrinkQuick API',
    version: '2.0',
    migration_support: true
  });
});

// ========== BASIC ROUTES ==========

// Home page
app.get('/', (req, res) => {
  res.json({ 
    success: true, 
    message: 'DrinkQuick API 🍹',
    version: '2.0',
    timestamp: new Date().toISOString(),
    status: '🟢 ONLINE',
    migration: {
      supported: true,
      backup_route: '/api/backup-data',
      verify_route: '/api/verify-migration',
      instructions: 'Visit /api/backup-data for migration SQL'
    },
    endpoints: [
      'POST /api/auth/register',
      'POST /api/auth/login',
      'GET /api/auth/me',
      'POST /api/auth/logout',
      'GET /api/drinks',
      'GET /api/backup-data',
      'GET /api/verify-migration',
      '/health',
      '/admin',
      '/debug-db'
    ]
  });
});

// Health check
app.get('/health', async (req, res) => {
  try {
    await pool.query('SELECT NOW()');
    const usersCount = await pool.query('SELECT COUNT(*) FROM users');
    
    res.json({ 
      success: true, 
      status: '✅ ONLINE', 
      database: '✅ CONNECTED',
      users: parseInt(usersCount.rows[0].count),
      time: new Date().toISOString(),
      migration_ready: true
    });
  } catch (error) {
    res.json({ 
      success: true, 
      status: '⚠️ ONLINE', 
      database: '❌ DISCONNECTED',
      error: error.message,
      migration_instructions: 'Fix database connection first'
    });
  }
});

// Debug database
app.get('/debug-db', async (req, res) => {
  try {
    const usersCount = await pool.query('SELECT COUNT(*) FROM users');
    const columnsResult = await pool.query(`
      SELECT column_name, data_type, is_nullable, column_default
      FROM information_schema.columns 
      WHERE table_name = 'users' AND table_schema = 'public'
      ORDER BY ordinal_position
    `);
    
    const dbInfo = await pool.query(`
      SELECT 
        current_database() as db_name,
        version() as db_version
    `);
    
    res.json({
      success: true,
      database: {
        name: dbInfo.rows[0].db_name,
        version: dbInfo.rows[0].db_version,
        provider: process.env.DATABASE_URL && process.env.DATABASE_URL.includes('neon.tech') ? 'Neon' : 'Render'
      },
      users: {
        total: parseInt(usersCount.rows[0].count)
      },
      columns: columnsResult.rows,
      hasDatabaseUrl: !!process.env.DATABASE_URL,
      url_preview: process.env.DATABASE_URL 
        ? process.env.DATABASE_URL.substring(0, 30) + '...' 
        : 'Not set',
      migration: {
        backup_available: true,
        endpoint: '/api/backup-data'
      }
    });
  } catch (error) {
    res.json({ 
      success: false, 
      error: error.message,
      hint: 'Check DATABASE_URL environment variable'
    });
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
      '/debug-db',
      '/api/auth/register',
      '/api/auth/login',
      '/api/auth/me',
      '/api/auth/logout',
      '/api/test',
      '/api/drinks',
      '/api/ping',
      '/api/backup-data',
      '/api/verify-migration',
      '/api/admin/users',
      '/api/admin/stats'
    ]
  });
});

// ========== START SERVER ==========
const PORT = process.env.PORT || 3000;
app.listen(PORT, '0.0.0.0', () => {
  console.log('\n🚀🚀🚀 DRINKQUICK SERVER v2.0 🚀🚀🚀');
  console.log('📍 Port:', PORT);
  console.log('🌐 URL: https://drink-quick-cal-kja1.onrender.com');
  console.log('📊 Database: PostgreSQL (Ready for Neon migration)');
  console.log('\n📋 MIGRATION ENDPOINTS:');
  console.log('   🔧 /api/backup-data - Get SQL for Neon import');
  console.log('   ✅ /api/verify-migration - Check migration status');
  console.log('\n🔑 AUTH ENDPOINTS:');
  console.log('   👤 POST /api/auth/register');
  console.log('   🔑 POST /api/auth/login (email OR username)');
  console.log('   👁️  GET /api/auth/me');
  console.log('\n🍹 APP ENDPOINTS:');
  console.log('   🍸 GET /api/drinks');
  console.log('   🧪 GET /api/test');
  console.log('   ❤️  GET /health');
  console.log('\n👑 ADMIN:');
  console.log('   📋 GET /api/admin/users (Bearer token: admin123)');
  console.log('   📊 GET /api/admin/stats');
  console.log('   🗑️  DELETE /api/admin/users/:id');
  console.log('========================================\n');
  console.log('🚨 IMPORTANT: Backup your data before Render DB expires!');
  console.log('   Visit: https://drink-quick-cal-kja1.onrender.com/api/backup-data');
  console.log('========================================\n');
});

