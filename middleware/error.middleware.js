const winston = require('winston');

const logger = winston.createLogger({
    level: 'error',
    format: winston.format.combine(
        winston.format.timestamp(),
        winston.format.json()
    ),
    transports: [
        new winston.transports.File({ filename: 'logs/error.log' }),
        new winston.transports.Console({
            format: winston.format.combine(
                winston.format.colorize(),
                winston.format.simple()
            )
        })
    ]
});

const errorHandler = (err, req, res, next) => {
    let error = {...err };
    error.message = err.message;

    // Log to console for dev
    console.error(err.stack);

    // Mongoose bad ObjectId
    if (err.name === 'CastError') {
        const message = 'Resource not found';
        error = { message, statusCode: 404 };
    }

    // Mongoose duplicate key
    if (err.code === 11000) {
        const field = Object.keys(err.keyPattern)[0];
        const message = `${field.charAt(0).toUpperCase() + field.slice(1)} already exists`;
        error = { message, statusCode: 400 };
    }

    // Mongoose validation error
    if (err.name === 'ValidationError') {
        const message = Object.values(err.errors).map(val => val.message).join(', ');
        error = { message, statusCode: 400 };
    }

    // JWT errors
    if (err.name === 'JsonWebTokenError') {
        const message = 'Invalid token';
        error = { message, statusCode: 401 };
    }

    if (err.name === 'TokenExpiredError') {
        const message = 'Token expired';
        error = { message, statusCode: 401 };
    }

    // Multer errors (file upload)
    if (err.name === 'MulterError') {
        let message = 'File upload error';
        if (err.code === 'LIMIT_FILE_SIZE') {
            message = 'File size too large';
        } else if (err.code === 'LIMIT_FILE_COUNT') {
            message = 'Too many files';
        } else if (err.code === 'LIMIT_UNEXPECTED_FILE') {
            message = 'Unexpected file field';
        }
        error = { message, statusCode: 400 };
    }

    // Log error
    logger.error({
        message: error.message,
        statusCode: error.statusCode || 500,
        path: req.path,
        method: req.method,
        ip: req.ip,
        userAgent: req.get('User-Agent'),
        userId: req.user ? req.user._id : null,
        stack: process.env.NODE_ENV === 'development' ? err.stack : undefined
    });

    res.status(error.statusCode || 500).json({
        status: 'error',
        message: error.message || 'Internal Server Error',
        stack: process.env.NODE_ENV === 'development' ? err.stack : undefined,
        ...(process.env.NODE_ENV === 'development' && { error: err.message })
    });
};

module.exports = errorHandler;