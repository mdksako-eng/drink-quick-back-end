const express = require('express');
const cors = require('cors');
const helmet = require('helmet');
const morgan = require('morgan');
const dotenv = require('dotenv');
const connectDB = require('./config/database');
const errorHandler = require('./middleware/error.middleware');
const winston = require('winston');

// Load environment variables
dotenv.config();

// Create logger
const logger = winston.createLogger({
    level: 'info',
    format: winston.format.combine(
        winston.format.timestamp(),
        winston.format.json()
    ),
    transports: [
        new winston.transports.File({ filename: 'logs/error.log', level: 'error' }),
        new winston.transports.File({ filename: 'logs/combined.log' }),
        new winston.transports.Console({
            format: winston.format.combine(
                winston.format.colorize(),
                winston.format.simple()
            )
        })
    ]
});

// Import routes
const authRoutes = require('./routes/auth.routes');
const drinkRoutes = require('./routes/drink.routes');
const orderRoutes = require('./routes/order.routes');
const userRoutes = require('./routes/user.routes');
const syncRoutes = require('./routes/sync.routes');

// Initialize express app
const app = express();

// Connect to database
connectDB();

// Middleware
app.use(helmet());
app.use(cors({
    origin: process.env.CLIENT_URL || 'http://localhost:3000',
    credentials: true
}));
app.use(morgan('dev'));
app.use(express.json());
app.use(express.urlencoded({ extended: true }));

// Request logging middleware
app.use((req, res, next) => {
    logger.info(`${req.method} ${req.url}`, {
        ip: req.ip,
        userAgent: req.get('User-Agent')
    });
    next();
});

// Health check route
app.get('/health', (req, res) => {
    res.status(200).json({
        status: 'success',
        message: 'Drinks Calculator API is running',
        timestamp: new Date().toISOString(),
        version: '1.0.0',
        environment: process.env.NODE_ENV
    });
});

// API Routes
app.use('/api/auth', authRoutes);
app.use('/api/drinks', drinkRoutes);
app.use('/api/orders', orderRoutes);
app.use('/api/users', userRoutes);
app.use('/api/sync', syncRoutes);

// Error handling middleware
app.use(errorHandler);

// 404 handler
app.use('*', (req, res) => {
    res.status(404).json({
        status: 'error',
        message: 'Route not found'
    });
});

const PORT = process.env.PORT || 5000;

const server = app.listen(PORT, () => {
    logger.info(`🚀 Server running on port ${PORT}`);
    logger.info(`📚 API: http://localhost:${PORT}`);
    logger.info(`🏥 Health: http://localhost:${PORT}/health`);
});

// Handle unhandled promise rejections
process.on('unhandledRejection', (err) => {
    logger.error('UNHANDLED REJECTION! 💥 Shutting down...');
    logger.error(err.name, err.message);
    server.close(() => {
        process.exit(1);
    });
});

// Handle uncaught exceptions
process.on('uncaughtException', (err) => {
    logger.error('UNCAUGHT EXCEPTION! 💥 Shutting down...');
    logger.error(err.name, err.message);
    process.exit(1);
});

module.exports = app;