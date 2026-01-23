const express = require('express');
const mongoose = require('mongoose');
const cors = require('cors');
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
            '/api/test'
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
        timestamp: new Date().toISOString()
    });
});

// ========== LOAD ROUTES ==========

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
            'GET /health'
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
            'GET /health'
        ]
    });
});

const PORT = process.env.PORT || 3000;
app.listen(PORT, '0.0.0.0', () => {
    console.log(`🚀 Server running on port ${PORT}`);
    console.log(`🌐 Local: http://localhost:${PORT}`);
    console.log(`📊 Health: http://localhost:${PORT}/health`);
    console.log(`👤 Auth test: http://localhost:${PORT}/api/auth/test`);
    console.log(`🍹 Drinks: http://localhost:${PORT}/api/drinks`);
    console.log(`🔄 Test endpoint: http://localhost:${PORT}/api/test`);
});
