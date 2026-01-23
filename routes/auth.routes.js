const express = require('express');
const router = express.Router();

// SIMPLE TEST ROUTES - NO VALIDATION, NO MIDDLEWARE
router.post('/register', (req, res) => {
    console.log('📱 Register request:', req.body);
    res.json({
        status: 'success',
        message: 'User registered successfully',
        data: {
            user: {
                _id: 'test_' + Date.now(),
                username: req.body.username,
                email: req.body.email,
                role: 'Customer'
            },
            token: 'test_token_' + Date.now(),
            refreshToken: 'test_refresh_' + Date.now()
        }
    });
});

router.post('/login', (req, res) => {
    console.log('📱 Login request:', req.body);
    res.json({
        status: 'success',
        message: 'Login successful',
        data: {
            user: {
                _id: 'test_user_123',
                username: req.body.username,
                email: req.body.username + '@test.com',
                role: 'Customer'
            },
            token: 'test_token_123',
            refreshToken: 'test_refresh_123'
        }
    });
});

router.get('/me', (req, res) => {
    const token = req.headers.authorization;
    console.log('📱 Get user profile, token:', token);
    res.json({
        status: 'success',
        data: {
            user: {
                _id: 'test_user_123',
                username: 'testuser',
                email: 'test@example.com',
                role: 'Customer'
            }
        }
    });
});

router.post('/logout', (req, res) => {
    res.json({
        status: 'success',
        message: 'Logged out successfully'
    });
});

module.exports = router;