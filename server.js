const express = require('express');
const mongoose = require('mongoose');
const cors = require('cors');
require('dotenv').config();

const app = express();

// Middleware
app.use(cors());
app.use(express.json());

// Test route
app.get('/', (req, res) => {
    res.json({ 
        message: 'Drink Quick API is running',
        version: '1.0.0',
        timestamp: new Date().toISOString(),
        endpoints: [
            '/api/drinks',
            '/health',
            '/api/drinks/health/route'
        ]
    });
});

// Health check
app.get('/health', (req, res) => {
    res.status(200).json({ 
        status: 'OK',
        database: mongoose.connection.readyState === 1 ? 'connected' : 'disconnected',
        uptime: process.uptime()
    });
});

// Load routes with error handling
try {
    const drinkRoutes = require('./routes/drink.routes');
    app.use('/api/drinks', drinkRoutes);
    console.log('✅ Drink routes loaded successfully');
} catch (error) {
    console.error('❌ Failed to load drink routes:', error.message);
    // Provide a fallback route
    app.use('/api/drinks', (req, res) => {
        res.status(503).json({ 
            error: 'Drink routes temporarily unavailable',
            message: error.message
        });
    });
}

// Test if routes are working
app.get('/api/test', (req, res) => {
    res.json({
        message: 'API test endpoint',
        working: true
    });
});

// MongoDB connection
const connectDB = async () => {
    try {
        const MONGODB_URI = process.env.MONGODB_URI || 'mongodb://localhost:27017/drinkquick';
        await mongoose.connect(MONGODB_URI, {
            useNewUrlParser: true,
            useUnifiedTopology: true,
        });
        console.log('✅ MongoDB Connected');
    } catch (error) {
        console.error('❌ MongoDB Connection Failed:', error.message);
        console.log('⚠️  Starting without database connection');
    }
};

connectDB();

// Error handling middleware
app.use((err, req, res, next) => {
    console.error('Server Error:', err.stack);
    res.status(500).json({
        error: 'Internal Server Error',
        message: process.env.NODE_ENV === 'development' ? err.message : 'Something went wrong'
    });
});

// CORRECT 404 handler - FIXED!
app.use((req, res) => {
    res.status(404).json({
        error: 'Route not found',
        path: req.originalUrl,
        method: req.method,
        availableEndpoints: [
            'GET /',
            'GET /health',
            'GET /api/test',
            'GET /api/drinks',
            'GET /api/drinks/:id',
            'POST /api/drinks',
            'PUT /api/drinks/:id',
            'DELETE /api/drinks/:id',
            'GET /api/drinks/health/route'
        ]
    });
});

const PORT = process.env.PORT || 3000;
app.listen(PORT, '0.0.0.0', () => {
    console.log(`🚀 Server running on port ${PORT}`);
    console.log(`🌐 Local: http://localhost:${PORT}`);
    console.log(`📊 Health: http://localhost:${PORT}/health`);
    console.log(`🍹 Drinks API: http://localhost:${PORT}/api/drinks`);
});
