const express = require('express');
const router = express.Router();

// SIMPLE TEST ROUTES - NO VALIDATION, NO MIDDLEWARE
router.post('/register', (req, res) => {
    console.log('📱 Register request:', req.body);
    
    // Return consistent response format
    res.status(201).json({
        success: true,
        message: 'User registered successfully',
        data: {
            user: {
                _id: 'test_' + Date.now(),
                username: req.body.username || req.body.email?.split('@')[0],
                email: req.body.email,
                role: 'Customer',
                securityQuestions: req.body.securityQuestions || {}
            },
            token: 'test_token_' + Date.now(),
            refreshToken: 'test_refresh_' + Date.now()
        }
    });
});

router.post('/login', (req, res) => {
    console.log('📱 Login request:', req.body);
    
    const username = req.body.username || req.body.email;
    const password = req.body.password;
    
    // Simple validation
    if (!username || !password) {
        return res.status(400).json({
            success: false,
            message: 'Username/email and password are required'
        });
    }
    
    res.json({
        success: true,
        message: 'Login successful',
        data: {
            user: {
                _id: 'test_user_123',
                username: username,
                email: username.includes('@') ? username : username + '@test.com',
                role: 'Customer',
                securityQuestions: {
                    'What is your pet\'s name?': 'Fluffy',
                    'What city were you born in?': 'New York'
                }
            },
            token: 'test_token_123',
            refreshToken: 'test_refresh_123'
        }
    });
});

router.get('/me', (req, res) => {
    const token = req.headers.authorization;
    console.log('📱 Get user profile, token:', token);
    
    if (!token) {
        return res.status(401).json({
            success: false,
            message: 'No token provided'
        });
    }
    
    res.json({
        success: true,
        data: {
            _id: 'test_user_123',
            username: 'testuser',
            email: 'test@example.com',
            role: 'Customer',
            securityQuestions: {
                'What is your pet\'s name?': 'Fluffy',
                'What city were you born in?': 'New York'
            }
        }
    });
});

router.post('/logout', (req, res) => {
    res.json({
        success: true,
        message: 'Logged out successfully'
    });
});

router.post('/refresh', (req, res) => {
    console.log('📱 Refresh token request:', req.body);
    
    res.json({
        success: true,
        token: 'new_test_token_' + Date.now()
    });
});

// Add a test endpoint
router.get('/test', (req, res) => {
    res.json({
        success: true,
        message: 'Auth API is working!',
        timestamp: new Date().toISOString(),
        endpoints: [
            'POST /register',
            'POST /login',
            'GET /me',
            'POST /logout',
            'POST /refresh',
            'GET /test'
        ]
    });
});

module.exports = router;
