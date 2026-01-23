const mongoose = require('mongoose');
const winston = require('winston');

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

const connectDB = async() => {
    try {
        const conn = await mongoose.connect(process.env.MONGODB_URI, {
            useNewUrlParser: true,
            useUnifiedTopology: true,
            serverSelectionTimeoutMS: 5000,
            socketTimeoutMS: 45000,
        });

        logger.info(`✅ MongoDB Connected: ${conn.connection.host}`);

        // Connection events
        mongoose.connection.on('error', (err) => {
            logger.error(`❌ MongoDB connection error: ${err}`);
        });

        mongoose.connection.on('disconnected', () => {
            logger.warn('⚠️ MongoDB disconnected');
        });

        mongoose.connection.on('reconnected', () => {
            logger.info('♻️ MongoDB reconnected');
        });

        // Graceful shutdown
        process.on('SIGINT', async() => {
            await mongoose.connection.close();
            logger.info('🔌 MongoDB connection closed through app termination');
            process.exit(0);
        });

    } catch (error) {
        logger.error(`❌ Database connection failed: ${error.message}`);

        // Retry connection after 5 seconds
        setTimeout(connectDB, 5000);
    }
};

module.exports = connectDB;