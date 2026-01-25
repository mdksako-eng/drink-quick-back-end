const express = require('express');
const mongoose = require('mongoose');
const cors = require('cors');
const path = require('path');
require('dotenv').config();

const app = express();

// CORS Configuration
const corsOptions = {
    origin: '*', // Allow all for testing
    methods: ['GET', 'POST', 'PUT', 'DELETE', 'PATCH', 'OPTIONS'],
    allowedHeaders: ['Content-Type', 'Authorization', 'Accept'],
    credentials: true,
    optionsSuccessStatus: 200
};

app.use(cors(corsOptions));
app.use(express.json());

// Serve static files from 'public' directory
app.use(express.static(path.join(__dirname, 'public')));

// ========== ADMIN ROUTES ==========
// Simple password-based admin authentication
const ADMIN_PASSWORD = process.env.ADMIN_PASSWORD || 'admin123';

// Middleware to verify admin
const verifyAdmin = (req, res, next) => {
  const authHeader = req.headers.authorization;
  
  if (!authHeader || !authHeader.startsWith('Bearer ')) {
    return res.status(401).json({ 
      success: false,
      message: 'Unauthorized - No token provided' 
    });
  }
  
  const token = authHeader.split(' ')[1];
  
  // Simple token check
  if (token === ADMIN_PASSWORD) {
    next();
  } else {
    res.status(403).json({ 
      success: false,
      message: 'Invalid admin credentials' 
    });
  }
};

// Admin API routes
app.get('/api/admin/users', verifyAdmin, async (req, res) => {
  try {
    // Assuming you have a User model
    const User = require('./models/User'); // Adjust path as needed
    
    const users = await User.find({}, '-password -__v').sort({ createdAt: -1 });
    
    res.json({
      success: true,
      count: users.length,
      users: users
    });
  } catch (error) {
    console.error('Error fetching users:', error);
    res.status(500).json({ 
      success: false,
      message: 'Server error fetching users' 
    });
  }
});

app.delete('/api/admin/users/:id', verifyAdmin, async (req, res) => {
  try {
    const User = require('./models/User');
    const deletedUser = await User.findByIdAndDelete(req.params.id);
    
    if (!deletedUser) {
      return res.status(404).json({ 
        success: false,
        message: 'User not found' 
      });
    }
    
    res.json({ 
      success: true,
      message: 'User deleted successfully',
      deletedUser: {
        id: deletedUser._id,
        name: deletedUser.name,
        email: deletedUser.email
      }
    });
  } catch (error) {
    console.error('Error deleting user:', error);
    res.status(500).json({ 
      success: false,
      message: 'Server error deleting user' 
    });
  }
});

// Admin stats endpoint
app.get('/api/admin/stats', verifyAdmin, async (req, res) => {
  try {
    const User = require('./models/User');
    const totalUsers = await User.countDocuments();
    
    const today = new Date();
    today.setHours(0, 0, 0, 0);
    const newToday = await User.countDocuments({ createdAt: { $gte: today } });
    
    res.json({
      success: true,
      totalUsers,
      newToday,
      timestamp: new Date().toISOString()
    });
  } catch (error) {
    res.status(500).json({ 
      success: false,
      message: 'Server error fetching stats' 
    });
  }
});

// Serve admin panel at /admin route
app.get('/admin', (req, res) => {
  res.sendFile(path.join(__dirname, 'public', 'admin.html'));
});

// Admin info endpoint (no auth required)
app.get('/api/admin/info', (req, res) => {
  res.json({
    success: true,
    message: 'Admin panel available at /admin',
    requiresPassword: true,
    endpoints: {
      users: 'GET /api/admin/users',
      deleteUser: 'DELETE /api/admin/users/:id',
      stats: 'GET /api/admin/stats'
    }
  });
});

// ========== EXISTING ROUTES ==========

// Test route
app.get('/', (req, res) => {
    res.json({ 
        success: true,
        message: 'Drink Quick API is running',
        version: '1.0.0',
        timestamp: new Date().toISOString(),
        endpoints: [
            '/api/auth/*',
            '/api/drinks/*',
            '/health',
            '/api/test',
            '/admin - User management panel',
            '/api/admin/* - Admin API'
        ]
    });
});

// Health check
app.get('/health', (req, res) => {
    res.status(200).json({ 
        success: true,
        status: 'OK',
        database: mongoose.connection.readyState === 1 ? 'connected' : 'disconnected',
        uptime: process.uptime(),
        timestamp: new Date().toISOString(),
        adminPanel: '/admin'
    });
});

// ========== LOAD YOUR EXISTING ROUTES ==========

// Auth routes
try {
    const authRoutes = require('./routes/auth.routes');
    app.use('/api/auth', authRoutes);
    console.log('✅ Auth routes loaded successfully');
} catch (error) {
    console.error('❌ Failed to load auth routes:', error.message);
    // Provide a fallback auth route
    app.use('/api/auth', (req, res) => {
        res.status(503).json({ 
            success: false,
            message: 'Auth routes temporarily unavailable'
        });
    });
}

// Drink routes
try {
    const drinkRoutes = require('./routes/drink.routes');
    app.use('/api/drinks', drinkRoutes);
    console.log('✅ Drink routes loaded successfully');
} catch (error) {
    console.error('❌ Failed to load drink routes:', error.message);
    // Provide a fallback route
    app.use('/api/drinks', (req, res) => {
        res.status(503).json({ 
            success: false,
            message: 'Drink routes temporarily unavailable'
        });
    });
}

// Test endpoint
app.get('/api/test', (req, res) => {
    res.json({
        success: true,
        message: 'API test endpoint',
        working: true,
        timestamp: new Date().toISOString(),
        availableEndpoints: [
            'POST /api/auth/register',
            'POST /api/auth/login',
            'GET /api/auth/me',
            'POST /api/auth/logout',
            'GET /api/drinks',
            '/health',
            '/admin - Admin panel',
            'GET /api/admin/users',
            'GET /api/admin/stats'
        ]
    });
});

// MongoDB connection
const connectDB = async () => {
    try {
        const MONGODB_URI = process.env.MONGODB_URI || 'mongodb://localhost:27017/drinkquick';
        if (MONGODB_URI && !MONGODB_URI.includes('localhost')) {
            await mongoose.connect(MONGODB_URI, {
                useNewUrlParser: true,
                useUnifiedTopology: true,
            });
            console.log('✅ MongoDB Connected');
        } else {
            console.log('⚠️  Running without MongoDB (test mode)');
        }
    } catch (error) {
        console.error('❌ MongoDB Connection Failed:', error.message);
        console.log('⚠️  Starting without database connection');
    }
};

connectDB();

// Error handling middleware
app.use((err, req, res, next) => {
    console.error('🚨 Server Error:', err.stack);
    res.status(500).json({
        success: false,
        message: 'Internal Server Error',
        error: process.env.NODE_ENV === 'development' ? err.message : undefined
    });
});

// 404 handler
app.use((req, res) => {
    res.status(404).json({
        success: false,
        message: 'Route not found',
        path: req.originalUrl,
        method: req.method,
        suggestions: [
            'POST /api/auth/register',
            'POST /api/auth/login',
            'GET /api/auth/me',
            'GET /api/drinks',
            '/health',
            '/admin - Admin panel'
        ]
    });
});

const PORT = process.env.PORT || 3000;
app.listen(PORT, '0.0.0.0', () => {
    console.log(`🚀 Server running on port ${PORT}`);
    console.log(`🌐 Local: http://localhost:${PORT}`);
    console.log(`📊 Health: http://localhost:${PORT}/health`);
    console.log(`🔐 Admin Panel: http://localhost:${PORT}/admin`);
    console.log(`👥 Admin API: http://localhost:${PORT}/api/admin/users`);
    console.log(`👤 Auth test: http://localhost:${PORT}/api/auth/test`);
    console.log(`🍹 Drinks: http://localhost:${PORT}/api/drinks`);
    console.log(`🔧 Admin password: ${ADMIN_PASSWORD || 'Not set (default: admin123)'}`);
});
