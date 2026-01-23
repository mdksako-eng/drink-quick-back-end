const jwt = require('jsonwebtoken');
const User = require('../models/User.model');

const protect = async(req, res, next) => {
    try {
        let token;

        if (req.headers.authorization && req.headers.authorization.startsWith('Bearer')) {
            token = req.headers.authorization.split(' ')[1];
        }

        if (!token) {
            return res.status(401).json({
                status: 'error',
                message: 'Not authorized, no token provided'
            });
        }

        // Verify token
        const decoded = jwt.verify(token, process.env.JWT_SECRET);

        // Get user from token
        const user = await User.findById(decoded.id).select('-password -refreshToken');

        if (!user) {
            return res.status(401).json({
                status: 'error',
                message: 'User not found'
            });
        }

        if (!user.isActive) {
            return res.status(401).json({
                status: 'error',
                message: 'User account is deactivated'
            });
        }

        // Check if account is locked
        if (user.lockUntil && user.lockUntil > Date.now()) {
            const remainingTime = Math.ceil((user.lockUntil - Date.now()) / 60000);
            return res.status(423).json({
                status: 'error',
                message: `Account is locked. Try again in ${remainingTime} minutes`
            });
        }

        req.user = user;
        next();
    } catch (error) {
        if (error.name === 'JsonWebTokenError') {
            return res.status(401).json({
                status: 'error',
                message: 'Not authorized, invalid token'
            });
        }

        if (error.name === 'TokenExpiredError') {
            return res.status(401).json({
                status: 'error',
                message: 'Token expired. Please login again'
            });
        }

        return res.status(401).json({
            status: 'error',
            message: 'Not authorized'
        });
    }
};

const authorize = (...roles) => {
    return (req, res, next) => {
        if (!roles.includes(req.user.role)) {
            return res.status(403).json({
                status: 'error',
                message: `User role ${req.user.role} is not authorized to access this route`
            });
        }
        next();
    };
};

const generateToken = (id) => {
    return jwt.sign({ id }, process.env.JWT_SECRET, {
        expiresIn: process.env.JWT_EXPIRE
    });
};

const generateRefreshToken = (id) => {
    return jwt.sign({ id }, process.env.JWT_REFRESH_SECRET, {
        expiresIn: process.env.JWT_REFRESH_EXPIRE
    });
};

module.exports = {
    protect,
    authorize,
    generateToken,
    generateRefreshToken
};