const express = require('express');
const router = express.Router();
const authController = require('../controllers/auth.controller');
const { protect, authorize } = require('../middleware/auth.middleware');
const { validate } = require('../middleware/validation.middleware');
const validators = require('../utils/validators');

// ============================================================
// PUBLIC ROUTES
// ============================================================
router.post('/register', validate(validators.registerValidation), authController.register);
router.post('/login', validate(validators.loginValidation), authController.login);
router.post('/refresh-token', authController.refreshToken);
router.post('/forgot-password', authController.forgotPassword);
router.post('/reset-password/:token', authController.resetPassword);
router.post('/reset-password-security', authController.resetPasswordWithSecurity);
router.post('/verify-security-questions', authController.verifySecurityQuestions);
router.get('/verify-reset-token/:token', authController.verifyResetToken);

// Test endpoint
router.get('/test', (req, res) => {
    res.json({
        success: true,
        message: 'Auth API is working!',
        timestamp: new Date().toISOString(),
        endpoints: [
            'POST /register', 'POST /login', 'GET /me', 'POST /logout',
            'POST /create-staff (Admin/Manager)',
            'POST /block-user/:id (Admin/Manager)',
            'POST /unblock-user/:id (Admin/Manager)',
            'DELETE /users/:id (Admin only)'
        ]
    });
});

// ============================================================
// PROTECTED ROUTES
// ============================================================
router.use(protect);

router.get('/me', authController.getMe);
router.post('/logout', authController.logout);
router.post('/change-password', validate(validators.changePasswordValidation), authController.changePassword);

// ============================================================
// STAFF/USER MANAGEMENT ROUTES
// ============================================================
router.post('/create-staff', authorize('Administrator', 'Manager'), authController.createStaff);
router.post('/block-user/:id', authorize('Administrator', 'Manager'), authController.blockUser);
router.post('/unblock-user/:id', authorize('Administrator', 'Manager'), authController.unblockUser);
router.delete('/users/:id', authorize('Administrator'), authController.deleteUser);

module.exports = router;
