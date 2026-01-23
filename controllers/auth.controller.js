const User = require('../models/User.model');
const { generateToken, generateRefreshToken } = require('../middleware/auth.middleware');
const { sanitizeUser } = require('../utils/helpers');
const { sendPasswordResetEmail, sendPasswordResetSuccessEmail, sendWelcomeEmail } = require('../utils/email.service');
const crypto = require('crypto');

// @desc    Register user
// @route   POST /api/auth/register
// @access  Public
const register = async(req, res) => {
    try {
        const { username, email, password, securityQuestions } = req.body;

        // Check if user exists
        const userExists = await User.findOne({
            $or: [{ username }, { email }]
        });

        if (userExists) {
            return res.status(400).json({
                status: 'error',
                message: 'User already exists'
            });
        }

        // Create user
        const user = await User.create({
            username,
            email,
            password,
            securityQuestions
        });

        // Generate tokens
        const token = generateToken(user._id);
        const refreshToken = generateRefreshToken(user._id);

        // Save refresh token
        user.refreshToken = refreshToken;
        await user.save();

        // Send welcome email
        try {
            await sendWelcomeEmail(user);
        } catch (emailError) {
            console.log('Welcome email failed:', emailError.message);
        }

        // Sanitize user data
        const userData = sanitizeUser(user);

        res.status(201).json({
            status: 'success',
            message: 'User registered successfully',
            data: {
                user: userData,
                token,
                refreshToken
            }
        });
    } catch (error) {
        console.error('Registration error:', error);
        res.status(500).json({
            status: 'error',
            message: 'Server error during registration'
        });
    }
};

// @desc    Login user
// @route   POST /api/auth/login
// @access  Public
const login = async(req, res) => {
    try {
        const { username, password } = req.body;

        // Check if user exists with password
        const user = await User.findOne({ username }).select('+password +loginAttempts +lockUntil');

        if (!user) {
            return res.status(401).json({
                status: 'error',
                message: 'Invalid credentials'
            });
        }

        // Check if account is locked
        if (user.isLocked()) {
            const remainingTime = Math.ceil((user.lockUntil - Date.now()) / 60000);
            return res.status(423).json({
                status: 'error',
                message: `Account is locked. Try again in ${remainingTime} minutes`
            });
        }

        // Check if account is active
        if (!user.isActive) {
            return res.status(401).json({
                status: 'error',
                message: 'Account is deactivated'
            });
        }

        // Check password
        const isPasswordMatch = await user.comparePassword(password);
        if (!isPasswordMatch) {
            // Increment login attempts
            await user.incrementLoginAttempts();

            return res.status(401).json({
                status: 'error',
                message: 'Invalid credentials'
            });
        }

        // Reset login attempts on successful login
        await user.resetLoginAttempts();

        // Update last login
        user.lastLogin = Date.now();
        await user.save();

        // Generate tokens
        const token = generateToken(user._id);
        const refreshToken = generateRefreshToken(user._id);

        // Save refresh token
        user.refreshToken = refreshToken;
        await user.save();

        // Sanitize user data
        const userData = sanitizeUser(user);

        res.json({
            status: 'success',
            message: 'Login successful',
            data: {
                user: userData,
                token,
                refreshToken
            }
        });
    } catch (error) {
        console.error('Login error:', error);
        res.status(500).json({
            status: 'error',
            message: 'Server error during login'
        });
    }
};

// @desc    Logout user
// @route   POST /api/auth/logout
// @access  Private
const logout = async(req, res) => {
    try {
        const user = await User.findById(req.user._id);

        if (user) {
            user.refreshToken = null;
            await user.save();
        }

        res.json({
            status: 'success',
            message: 'Logged out successfully'
        });
    } catch (error) {
        console.error('Logout error:', error);
        res.status(500).json({
            status: 'error',
            message: 'Server error during logout'
        });
    }
};

// @desc    Refresh token
// @route   POST /api/auth/refresh-token
// @access  Public
const refreshToken = async(req, res) => {
    try {
        const { refreshToken } = req.body;

        if (!refreshToken) {
            return res.status(401).json({
                status: 'error',
                message: 'Refresh token required'
            });
        }

        const user = await User.findOne({ refreshToken }).select('+refreshToken');

        if (!user) {
            return res.status(401).json({
                status: 'error',
                message: 'Invalid refresh token'
            });
        }

        // Generate new tokens
        const newToken = generateToken(user._id);
        const newRefreshToken = generateRefreshToken(user._id);

        // Update refresh token
        user.refreshToken = newRefreshToken;
        await user.save();

        res.json({
            status: 'success',
            data: {
                token: newToken,
                refreshToken: newRefreshToken
            }
        });
    } catch (error) {
        console.error('Refresh token error:', error);
        res.status(500).json({
            status: 'error',
            message: 'Server error during token refresh'
        });
    }
};

// @desc    Request password reset
// @route   POST /api/auth/forgot-password
// @access  Public
const forgotPassword = async(req, res) => {
    try {
        const { email } = req.body;

        // Find user by email
        const user = await User.findOne({ email });

        if (!user) {
            // For security, don't reveal if user exists
            return res.json({
                status: 'success',
                message: 'If your email exists, you will receive a password reset link'
            });
        }

        // Generate reset token
        const resetToken = user.generatePasswordResetToken();
        await user.save();

        // Create reset URL
        const resetUrl = `${process.env.PASSWORD_RESET_URL}/${resetToken}`;

        try {
            // Send email
            await sendPasswordResetEmail(user, resetUrl);

            res.json({
                status: 'success',
                message: 'Password reset email sent'
            });
        } catch (emailError) {
            // Remove reset token if email fails
            user.resetPasswordToken = undefined;
            user.resetPasswordExpire = undefined;
            await user.save();

            throw emailError;
        }
    } catch (error) {
        console.error('Forgot password error:', error);
        res.status(500).json({
            status: 'error',
            message: 'Server error during password reset request'
        });
    }
};

// @desc    Reset password with token
// @route   POST /api/auth/reset-password/:token
// @access  Public
const resetPassword = async(req, res) => {
    try {
        const { token } = req.params;
        const { newPassword } = req.body;

        // Find user by reset token
        const user = await User.findByResetToken(token);

        if (!user) {
            return res.status(400).json({
                status: 'error',
                message: 'Invalid or expired reset token'
            });
        }

        // Update password
        user.password = newPassword;
        user.resetPasswordToken = undefined;
        user.resetPasswordExpire = undefined;
        await user.save();

        // Send success email
        try {
            await sendPasswordResetSuccessEmail(user);
        } catch (emailError) {
            console.log('Success email failed:', emailError.message);
        }

        res.json({
            status: 'success',
            message: 'Password reset successfully'
        });
    } catch (error) {
        console.error('Reset password error:', error);
        res.status(500).json({
            status: 'error',
            message: 'Server error during password reset'
        });
    }
};

// @desc    Reset password with security questions
// @route   POST /api/auth/reset-password-security
// @access  Public
const resetPasswordWithSecurity = async(req, res) => {
    try {
        const { username, email, securityAnswers, newPassword } = req.body;

        // Find user
        const user = await User.findOne({ username, email });

        if (!user) {
            return res.status(404).json({
                status: 'error',
                message: 'User not found'
            });
        }

        // Verify security answers
        if (
            user.securityQuestions.question1 !== securityAnswers.question1 ||
            user.securityQuestions.question2 !== securityAnswers.question2
        ) {
            return res.status(401).json({
                status: 'error',
                message: 'Security answers are incorrect'
            });
        }

        // Update password
        user.password = newPassword;
        await user.save();

        // Send success email
        try {
            await sendPasswordResetSuccessEmail(user);
        } catch (emailError) {
            console.log('Success email failed:', emailError.message);
        }

        res.json({
            status: 'success',
            message: 'Password reset successfully'
        });
    } catch (error) {
        console.error('Password reset error:', error);
        res.status(500).json({
            status: 'error',
            message: 'Server error during password reset'
        });
    }
};

// @desc    Get current user
// @route   GET /api/auth/me
// @access  Private
const getMe = async(req, res) => {
    try {
        const user = await User.findById(req.user._id);

        if (!user) {
            return res.status(404).json({
                status: 'error',
                message: 'User not found'
            });
        }

        const userData = sanitizeUser(user);

        res.json({
            status: 'success',
            data: {
                user: userData
            }
        });
    } catch (error) {
        console.error('Get me error:', error);
        res.status(500).json({
            status: 'error',
            message: 'Server error'
        });
    }
};

// @desc    Verify reset token
// @route   GET /api/auth/verify-reset-token/:token
// @access  Public
const verifyResetToken = async(req, res) => {
    try {
        const { token } = req.params;

        // Find user by reset token
        const user = await User.findByResetToken(token);

        if (!user) {
            return res.status(400).json({
                status: 'error',
                message: 'Invalid or expired reset token'
            });
        }

        res.json({
            status: 'success',
            message: 'Token is valid',
            data: {
                email: user.email,
                username: user.username
            }
        });
    } catch (error) {
        console.error('Verify token error:', error);
        res.status(500).json({
            status: 'error',
            message: 'Server error'
        });
    }
};

// @desc    Change password (logged in user)
// @route   POST /api/auth/change-password
// @access  Private
const changePassword = async(req, res) => {
    try {
        const { currentPassword, newPassword } = req.body;
        const userId = req.user._id;

        // Get user with password
        const user = await User.findById(userId).select('+password');

        if (!user) {
            return res.status(404).json({
                status: 'error',
                message: 'User not found'
            });
        }

        // Check current password
        const isPasswordMatch = await user.comparePassword(currentPassword);
        if (!isPasswordMatch) {
            return res.status(401).json({
                status: 'error',
                message: 'Current password is incorrect'
            });
        }

        // Update password
        user.password = newPassword;
        await user.save();

        res.json({
            status: 'success',
            message: 'Password changed successfully'
        });
    } catch (error) {
        console.error('Change password error:', error);
        res.status(500).json({
            status: 'error',
            message: 'Server error during password change'
        });
    }
};

// @desc    Verify security questions
// @route   POST /api/auth/verify-security-questions
// @access  Public
const verifySecurityQuestions = async(req, res) => {
    try {
        const { username, email, securityAnswers } = req.body;

        // Find user
        const user = await User.findOne({ username, email });

        if (!user) {
            return res.status(404).json({
                status: 'error',
                message: 'User not found'
            });
        }

        // Verify security answers
        if (
            user.securityQuestions.question1 !== securityAnswers.question1 ||
            user.securityQuestions.question2 !== securityAnswers.question2
        ) {
            return res.status(401).json({
                status: 'error',
                message: 'Security answers are incorrect'
            });
        }

        res.json({
            status: 'success',
            message: 'Security questions verified successfully'
        });
    } catch (error) {
        console.error('Verify security questions error:', error);
        res.status(500).json({
            status: 'error',
            message: 'Server error'
        });
    }
};

module.exports = {
    register,
    login,
    logout,
    refreshToken,
    forgotPassword,
    resetPassword,
    resetPasswordWithSecurity,
    getMe,
    verifyResetToken,
    changePassword,
    verifySecurityQuestions
};