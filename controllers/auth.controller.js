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
                message: 'Account is deactivated. Contact your manager.'
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
            await sendPasswordResetEmail(user, resetUrl);
            res.json({
                status: 'success',
                message: 'Password reset email sent'
            });
        } catch (emailError) {
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

        const user = await User.findByResetToken(token);

        if (!user) {
            return res.status(400).json({
                status: 'error',
                message: 'Invalid or expired reset token'
            });
        }

        user.password = newPassword;
        user.resetPasswordToken = undefined;
        user.resetPasswordExpire = undefined;
        await user.save();

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

        const user = await User.findOne({ username, email });

        if (!user) {
            return res.status(404).json({
                status: 'error',
                message: 'User not found'
            });
        }

        if (
            user.securityQuestions.question1 !== securityAnswers.question1 ||
            user.securityQuestions.question2 !== securityAnswers.question2
        ) {
            return res.status(401).json({
                status: 'error',
                message: 'Security answers are incorrect'
            });
        }

        user.password = newPassword;
        await user.save();

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
            data: { user: userData }
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

        const user = await User.findById(userId).select('+password');

        if (!user) {
            return res.status(404).json({
                status: 'error',
                message: 'User not found'
            });
        }

        const isPasswordMatch = await user.comparePassword(currentPassword);
        if (!isPasswordMatch) {
            return res.status(401).json({
                status: 'error',
                message: 'Current password is incorrect'
            });
        }

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

        const user = await User.findOne({ username, email });

        if (!user) {
            return res.status(404).json({
                status: 'error',
                message: 'User not found'
            });
        }

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

// ============================================================
// STAFF MANAGEMENT FUNCTIONS (NEW)
// ============================================================

// @desc    Create staff (Admin or Manager only)
// @route   POST /api/auth/create-staff
// @access  Private (Admin and Manager)
const createStaff = async(req, res) => {
    try {
        const { username, email, password, securityQuestions } = req.body;

        // Only Admin or Manager can create staff
        if (req.user.role !== 'Administrator' && req.user.role !== 'Manager') {
            return res.status(403).json({
                status: 'error',
                message: 'Only Administrator or Manager can create staff accounts'
            });
        }

        // Manager must have a company
        if (req.user.role === 'Manager' && !req.user.companyId) {
            return res.status(400).json({
                status: 'error',
                message: 'Manager must belong to a company to create staff'
            });
        }

        // Check if user already exists
        const userExists = await User.findOne({
            $or: [{ username }, { email }]
        });

        if (userExists) {
            return res.status(400).json({
                status: 'error',
                message: 'Username or email already exists'
            });
        }

        // Create staff user with same company as creator
        const user = await User.create({
            username,
            email,
            password,
            role: 'Staff',
            securityQuestions: {
                question1: securityQuestions?.question1 || securityQuestions?.answer1 || '',
                question2: securityQuestions?.question2 || securityQuestions?.answer2 || ''
            },
            companyId: req.user.companyId || null // Same company as creator
        });

        const userData = sanitizeUser(user);

        res.status(201).json({
            status: 'success',
            message: 'Staff account created successfully',
            data: {
                user: userData,
                createdBy: req.user.username,
                createdByRole: req.user.role,
                companyId: user.companyId
            }
        });
    } catch (error) {
        console.error('Create staff error:', error);
        res.status(500).json({
            status: 'error',
            message: 'Server error during staff creation'
        });
    }
};

// @desc    Block staff (Admin or Manager - same company)
// @route   POST /api/auth/block-staff/:id
// @access  Private (Admin and Manager)
const blockStaff = async(req, res) => {
    try {
        const staffId = req.params.id;

        // Find the staff user
        const staff = await User.findById(staffId);

        if (!staff) {
            return res.status(404).json({
                status: 'error',
                message: 'Staff not found'
            });
        }

        // Only Admin or Manager can block
        if (req.user.role !== 'Administrator' && req.user.role !== 'Manager') {
            return res.status(403).json({
                status: 'error',
                message: 'Not authorized to block staff'
            });
        }

        // Manager can only block staff from their own company
        if (req.user.role === 'Manager') {
            if (!req.user.companyId) {
                return res.status(400).json({
                    status: 'error',
                    message: 'Manager must belong to a company'
                });
            }
            
            // Compare company IDs
            const creatorCompanyId = req.user.companyId.toString();
            const staffCompanyId = staff.companyId ? staff.companyId.toString() : null;
            
            if (staffCompanyId !== creatorCompanyId) {
                return res.status(403).json({
                    status: 'error',
                    message: 'You can only manage staff from your own company'
                });
            }
        }

        // Only allow blocking Staff role (not Admin or Manager)
        if (staff.role !== 'Staff') {
            return res.status(400).json({
                status: 'error',
                message: 'Can only block staff accounts, not admin or manager accounts'
            });
        }

        // Block the staff
        staff.isActive = false;
        await staff.save();

        res.json({
            status: 'success',
            message: `${staff.username} has been blocked successfully`,
            data: {
                user: {
                    id: staff._id,
                    username: staff.username,
                    email: staff.email,
                    role: staff.role,
                    isActive: false
                }
            }
        });
    } catch (error) {
        console.error('Block staff error:', error);
        res.status(500).json({
            status: 'error',
            message: 'Server error while blocking staff'
        });
    }
};

// @desc    Unblock staff (Admin or Manager - same company)
// @route   POST /api/auth/unblock-staff/:id
// @access  Private (Admin and Manager)
const unblockStaff = async(req, res) => {
    try {
        const staffId = req.params.id;

        // Find the staff user
        const staff = await User.findById(staffId);

        if (!staff) {
            return res.status(404).json({
                status: 'error',
                message: 'Staff not found'
            });
        }

        // Only Admin or Manager can unblock
        if (req.user.role !== 'Administrator' && req.user.role !== 'Manager') {
            return res.status(403).json({
                status: 'error',
                message: 'Not authorized to unblock staff'
            });
        }

        // Manager can only unblock staff from their own company
        if (req.user.role === 'Manager') {
            if (!req.user.companyId) {
                return res.status(400).json({
                    status: 'error',
                    message: 'Manager must belong to a company'
                });
            }
            
            const creatorCompanyId = req.user.companyId.toString();
            const staffCompanyId = staff.companyId ? staff.companyId.toString() : null;
            
            if (staffCompanyId !== creatorCompanyId) {
                return res.status(403).json({
                    status: 'error',
                    message: 'You can only manage staff from your own company'
                });
            }
        }

        // Unblock the staff
        staff.isActive = true;
        await staff.save();

        res.json({
            status: 'success',
            message: `${staff.username} has been unblocked successfully`,
            data: {
                user: {
                    id: staff._id,
                    username: staff.username,
                    email: staff.email,
                    role: staff.role,
                    isActive: true
                }
            }
        });
    } catch (error) {
        console.error('Unblock staff error:', error);
        res.status(500).json({
            status: 'error',
            message: 'Server error while unblocking staff'
        });
    }
};

// @desc    Delete staff permanently (Admin only)
// @route   DELETE /api/auth/delete-staff/:id
// @access  Private (Admin only)
const deleteStaff = async(req, res) => {
    try {
        const staffId = req.params.id;

        // Only Admin can permanently delete
        if (req.user.role !== 'Administrator') {
            return res.status(403).json({
                status: 'error',
                message: 'Only Administrator can permanently delete staff accounts'
            });
        }

        const staff = await User.findById(staffId);

        if (!staff) {
            return res.status(404).json({
                status: 'error',
                message: 'Staff not found'
            });
        }

        // Only allow deleting Staff role
        if (staff.role !== 'Staff') {
            return res.status(400).json({
                status: 'error',
                message: 'Can only delete staff accounts'
            });
        }

        await User.findByIdAndDelete(staffId);

        res.json({
            status: 'success',
            message: `${staff.username} has been permanently deleted`
        });
    } catch (error) {
        console.error('Delete staff error:', error);
        res.status(500).json({
            status: 'error',
            message: 'Server error while deleting staff'
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
    verifySecurityQuestions,
    createStaff,
    blockStaff,
    unblockStaff,
    deleteStaff
};
