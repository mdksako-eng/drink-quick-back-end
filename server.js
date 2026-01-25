const express = require('express');
const cors = require('cors');
const path = require('path');
require('dotenv').config();

const app = express();

// CORS Configuration
const corsOptions = {
    origin: '*',
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

// Mock user data
const mockUsers = [
  { 
    _id: '1', 
    username: 'Admin User',
    name: 'Admin User',
    email: 'admin@drinkquick.com', 
    createdAt: new Date('2024-01-20T10:30:00Z'), 
    updatedAt: new Date('2024-01-25T14:20:00Z'),
    isAdmin: true,
    role: 'Administrator',
    isActive: true,
    emailVerified: true,
    lastLogin: new Date('2024-01-25T14:15:00Z'),
    profileImage: 'https://i.pravatar.cc/150?img=1'
  },
  { 
    _id: '2', 
    username: 'John Doe',
    name: 'John Doe',
    email: 'john@example.com', 
    createdAt: new Date('2024-01-22T11:45:00Z'), 
    updatedAt: new Date('2024-01-24T09:10:00Z'),
    isAdmin: false,
    role: 'Customer',
    isActive: true,
    emailVerified: true,
    lastLogin: new Date('2024-01-24T09:10:00Z'),
    profileImage: 'https://i.pravatar.cc/150?img=2'
  },
  { 
    _id: '3', 
    username: 'Jane Smith',
    name: 'Jane Smith',
    email: 'jane@example.com', 
    createdAt: new Date('2024-01-23T14:20:00Z'), 
    updatedAt: new Date('2024-01-25T16:45:00Z'),
    isAdmin: false,
    role: 'Customer',
    isActive: true,
    emailVerified: false,
    lastLogin: new Date('2024-01-25T16:45:00Z'),
    profileImage: 'https://i.pravatar.cc/150?img=3'
  },
  { 
    _id: '4', 
    username: 'Manager Bob',
    name: 'Manager Bob',
    email: 'manager@drinkquick.com', 
    createdAt: new Date('2024-01-24T08:15:00Z'), 
    updatedAt: new Date('2024-01-25T12:30:00Z'),
    isAdmin: false,
    role: 'Manager',
    isActive: true,
    emailVerified: true,
    lastLogin: new Date('2024-01-25T12:30:00Z'),
    profileImage: 'https://i.pravatar.cc/150?img=4'
  },
  { 
    _id: '5', 
    username: 'Inactive User',
    name: 'Inactive User',
    email: 'inactive@example.com', 
    createdAt: new Date('2024-01-10T09:00:00Z'), 
    updatedAt: new Date('2024-01-20T11:00:00Z'),
    isAdmin: false,
    role: 'Customer',
    isActive: false,
    emailVerified: false,
    lastLogin: new Date('2024-01-20T11:00:00Z'),
    profileImage: ''
  }
];

// Admin API routes with mock data
app.get('/api/admin/users', verifyAdmin, (req, res) => {
  try {
    // Optional: Filter by search query
    const searchTerm = req.query.search?.toLowerCase() || '';
    const filteredUsers = searchTerm 
      ? mockUsers.filter(user => 
          user.name.toLowerCase().includes(searchTerm) ||
          user.email.toLowerCase().includes(searchTerm) ||
          user.role.toLowerCase().includes(searchTerm)
        )
      : mockUsers;
    
    res.json({
      success: true,
      count: filteredUsers.length,
      users: filteredUsers
    });
  } catch (error) {
    console.error('Error fetching users:', error);
    res.status(500).json({ 
      success: false,
      message: 'Server error fetching users' 
    });
  }
});

app.delete('/api/admin/users/:id', verifyAdmin, (req, res) => {
  try {
    const userId = req.params.id;
    const userIndex = mockUsers.findIndex(user => user._id === userId);
    
    if (userIndex === -1) {
      return res.status(404).json({ 
        success: false,
        message: 'User not found' 
      });
    }
    
    const deletedUser = mockUsers[userIndex];
    mockUsers.splice(userIndex, 1);
    
    res.json({ 
      success: true,
      message: 'User deleted successfully',
      deletedUser: {
        id: deletedUser._id,
        name: deletedUser.name,
        email: deletedUser.email,
        role: deletedUser.role
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

// Admin stats endpoint with mock data
app.get('/api/admin/stats', verifyAdmin, (req, res) => {
  try {
    const today = new Date();
    today.setHours(0, 0, 0, 0);
    
    const newToday = mockUsers.filter(user => 
      new Date(user.createdAt) >= today
    ).length;
    
    // Count by role
    const roleCounts = {};
    mockUsers.forEach(user => {
      roleCounts[user.role] = (roleCounts[user.role] || 0) + 1;
    });
    
    // Count active/inactive
    const activeUsers = mockUsers.filter(user => user.isActive).length;
    const verifiedUsers = mockUsers.filter(user => user.emailVerified).length;
    
    res.json({
      success: true,
      totalUsers: mockUsers.length,
      newToday,
      activeUsers,
      verifiedUsers,
      roleCounts,
      timestamp: new Date().toISOString()
    });
  } catch (error) {
    console.error('Error fetching stats:', error);
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

// Health check (without MongoDB)
app.get('/health', (req, res) => {
    res.status(200).json({ 
        success: true,
        status: 'OK',
        database: 'mock_data_mode',
        uptime: process.uptime(),
        timestamp: new Date().toISOString(),
        adminPanel: '/admin'
    });
});

// ========== LOAD YOUR EXISTING ROUTES ==========

// Auth routes (mock version to avoid errors)
try {
    const authRoutes = require('./routes/auth.routes');
    app.use('/api/auth', authRoutes);
    console.log('✅ Auth routes loaded successfully');
} catch (error) {
    console.error('❌ Failed to load auth routes:', error.message);
    // Provide a mock auth route
    app.use('/api/auth', (req, res) => {
        res.status(200).json({ 
            success: true,
            message: 'Auth API (mock mode)',
            endpoints: ['/register', '/login', '/logout', '/me']
        });
    });
}

// Drink routes (mock version to avoid errors)
try {
    const drinkRoutes = require('./routes/drink.routes');
    app.use('/api/drinks', drinkRoutes);
    console.log('✅ Drink routes loaded successfully');
} catch (error) {
    console.error('❌ Failed to load drink routes:', error.message);
    // Provide a mock drink route
    app.use('/api/drinks', (req, res) => {
        res.status(200).json({ 
            success: true,
            message: 'Drinks API (mock mode)',
            drinks: [
                { id: 1, name: 'Mojito', category: 'Cocktail', price: 8.99 },
                { id: 2, name: 'Margarita', category: 'Cocktail', price: 9.99 },
                { id: 3, name: 'Beer', category: 'Beer', price: 5.99 }
            ]
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
            '/',
            '/health',
            '/admin',
            '/api/test',
            '/api/admin/info'
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
    console.log(`📱 Mode: Using mock data (no MongoDB connection)`);
});
