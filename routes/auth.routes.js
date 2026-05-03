const User = require('../models/User.model');
const { generateToken, generateRefreshToken } = require('../middleware/auth.middleware');
const { sanitizeUser } = require('../utils/helpers');
const { sendPasswordResetEmail, sendPasswordResetSuccessEmail, sendWelcomeEmail } = require('../utils/email.service');
const crypto = require('crypto');

// ============================================================
// AUTHENTICATION FUNCTIONS
// ============================================================

// @desc    Register user
// @route   POST /api/auth/register
// @access  Public
const register = async(req, res) => {
    try {
        const { username, email, password, securityQuestions } = req.body;

        const userExists = await User.findOne({
            $or: [{ username }, { email }]
        });

        if (userExists) {
            return res.status(400).json({
                status: 'error',
                message: 'User already exists'
            });
        }

        const user = await User.create({
            username,
            email,
            password,
            securityQuestions
        });

        const token = generateToken(user._id);
        const refreshToken = generateRefreshToken(user._id);

        user.refreshToken = refreshToken;
        await user.save();

        try {
            await sendWelcomeEmail(user);
        } catch (emailError) {
            console.log('Welcome email failed:', emailError.message);
        }

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

        const user = await User.findOne({ username }).select('+password +loginAttempts +lockUntil');

        if (!user) {
            return res.status(401).json({
                status: 'error',
                message: 'Invalid credentials'
            });
        }

        if (user.isLocked()) {
            const remainingTime = Math.ceil((user.lockUntil - Date.now()) / 60000);
            return res.status(423).json({
                status: 'error',
                message: `Account is locked. Try again in ${remainingTime} minutes`
            });
        }

        if (!user.isActive) {
            return res.status(401).json({
                status: 'error',
                message: 'Account is deactivated. Contact your administrator.'
            });
        }

        const isPasswordMatch = await user.comparePassword(password);
        if (!isPasswordMatch) {
            await user.incrementLoginAttempts();
            return res.status(401).json({
                status: 'error',
                message: 'Invalid credentials'
            });
        }

        await user.resetLoginAttempts();
        user.lastLogin = Date.now();

        const token = generateToken(user._id);
        const refreshToken = generateRefreshToken(user._id);
        user.refreshToken = refreshToken;
        await user.save();

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
        const newToken = generateToken(user._id);
        const newRefreshToken = generateRefreshToken(user._id);
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
        const user = await User.findOne({ email });
        if (!user) {
            return res.json({
                status: 'success',
                message: 'If your email exists, you will receive a password reset link'
            });
        }
        const resetToken = user.generatePasswordResetToken();
        await user.save();
        const resetUrl = `${process.env.PASSWORD_RESET_URL || 'http://localhost:3000/reset-password'}/${resetToken}`;
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
// USER MANAGEMENT FUNCTIONS (Admin & Manager)
// ============================================================

// @desc    Create staff (Admin or Manager)
// @route   POST /api/auth/create-staff
// @access  Private (Admin and Manager)
const createStaff = async(req, res) => {
    try {
        const { username, email, password, securityQuestions } = req.body;

        if (req.user.role !== 'Administrator' && req.user.role !== 'Manager') {
            return res.status(403).json({
                status: 'error',
                message: 'Only Administrator or Manager can create staff accounts'
            });
        }

        if (req.user.role === 'Manager' && !req.user.companyId) {
            return res.status(400).json({
                status: 'error',
                message: 'Manager must belong to a company to create staff'
            });
        }

        const userExists = await User.findOne({
            $or: [{ username }, { email }]
        });

        if (userExists) {
            return res.status(400).json({
                status: 'error',
                message: 'Username or email already exists'
            });
        }

        const user = await User.create({
            username,
            email,
            password,
            role: 'Staff',
            securityQuestions: {
                question1: securityQuestions?.question1 || securityQuestions?.answer1 || '',
                question2: securityQuestions?.question2 || securityQuestions?.answer2 || ''
            },
            companyId: req.user.companyId || null
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

// @desc    Block any user (Admin: anyone except self/admins, Manager: only Staff in their company)
// @route   POST /api/auth/block-user/:id
// @access  Private (Admin and Manager)
const blockUser = async(req, res) => {
    try {
        const userId = req.params.id;

        const user = await User.findById(userId);

        if (!user) {
            return res.status(404).json({
                status: 'error',
                message: 'User not found'
            });
        }

        // Only Admin or Manager can block
        if (req.user.role !== 'Administrator' && req.user.role !== 'Manager') {
            return res.status(403).json({
                status: 'error',
                message: 'Not authorized to block users'
            });
        }

        // Cannot block yourself
        if (userId === req.user._id.toString()) {
            return res.status(400).json({
                status: 'error',
                message: 'You cannot block your own account'
            });
        }

        // Cannot block another Admin
        if (user.role === 'Administrator') {
            return res.status(403).json({
                status: 'error',
                message: 'Cannot block an Administrator account'
            });
        }

        // Manager restrictions
        if (req.user.role === 'Manager') {
            // Manager cannot block other Managers
            if (user.role === 'Manager') {
                return res.status(403).json({
                    status: 'error',
                    message: 'Managers cannot block other Managers'
                });
            }

            // Manager can only block users from their company
            if (!req.user.companyId) {
                return res.status(400).json({
                    status: 'error',
                    message: 'Manager must belong to a company'
                });
            }

            const managerCompanyId = req.user.companyId.toString();
            const userCompanyId = user.companyId ? user.companyId.toString() : null;

            if (userCompanyId !== managerCompanyId) {
                return res.status(403).json({
                    status: 'error',
                    message: 'You can only manage users from your own company'
                });
            }

            // Manager can only block Staff, not other roles
            if (user.role !== 'Staff' && user.role !== 'Customer') {
                return res.status(403).json({
                    status: 'error',
                    message: 'Manager can only block Staff or Customer accounts'
                });
            }
        }

        user.isActive = false;
        await user.save();

        res.json({
            status: 'success',
            message: `${user.role} '${user.username}' has been blocked successfully`,
            data: {
                user: {
                    id: user._id,
                    username: user.username,
                    email: user.email,
                    role: user.role,
                    isActive: false,
                    companyId: user.companyId
                }
            }
        });
    } catch (error) {
        console.error('Block user error:', error);
        res.status(500).json({
            status: 'error',
            message: 'Server error while blocking user'
        });
    }
};

// @desc    Unblock any user (Admin: anyone, Manager: only Staff in their company)
// @route   POST /api/auth/unblock-user/:id
// @access  Private (Admin and Manager)
const unblockUser = async(req, res) => {
    try {
        const userId = req.params.id;

        const user = await User.findById(userId);

        if (!user) {
            return res.status(404).json({
                status: 'error',
                message: 'User not found'
            });
        }

        // Only Admin or Manager can unblock
        if (req.user.role !== 'Administrator' && req.user.role !== 'Manager') {
            return res.status(403).json({
                status: 'error',
                message: 'Not authorized to unblock users'
            });
        }

        // Admin can unblock anyone
        if (req.user.role === 'Administrator') {
            user.isActive = true;
            await user.save();

            return res.json({
                status: 'success',
                message: `${user.role} '${user.username}' has been unblocked successfully`,
                data: {
                    user: {
                        id: user._id,
                        username: user.username,
                        email: user.email,
                        role: user.role,
                        isActive: true,
                        companyId: user.companyId
                    }
                }
            });
        }

        // Manager restrictions
        if (req.user.role === 'Manager') {
            if (!req.user.companyId) {
                return res.status(400).json({
                    status: 'error',
                    message: 'Manager must belong to a company'
                });
            }

            const managerCompanyId = req.user.companyId.toString();
            const userCompanyId = user.companyId ? user.companyId.toString() : null;

            if (userCompanyId !== managerCompanyId) {
                return res.status(403).json({
                    status: 'error',
                    message: 'You can only manage users from your own company'
                });
            }
        }

        user.isActive = true;
        await user.save();

        res.json({
            status: 'success',
            message: `${user.role} '${user.username}' has been unblocked successfully`,
            data: {
                user: {
                    id: user._id,
                    username: user.username,
                    email: user.email,
                    role: user.role,
                    isActive: true,
                    companyId: user.companyId
                }
            }
        });
    } catch (error) {
        console.error('Unblock user error:', error);
        res.status(500).json({
            status: 'error',
            message: 'Server error while unblocking user'
        });
    }
};

// @desc    Delete any user permanently (Admin only)
// @route   DELETE /api/auth/users/:id
// @access  Private (Admin only)
const deleteUser = async(req, res) => {
    try {
        const userId = req.params.id;

        // Only Admin can delete users
        if (req.user.role !== 'Administrator') {
            return res.status(403).json({
                status: 'error',
                message: 'Only Administrator can delete user accounts'
            });
        }

        // Prevent admin from deleting themselves
        if (userId === req.user._id.toString()) {
            return res.status(400).json({
                status: 'error',
                message: 'You cannot delete your own account'
            });
        }

        const user = await User.findById(userId);

        if (!user) {
            return res.status(404).json({
                status: 'error',
                message: 'User not found'
            });
        }

        // Prevent deleting another Admin
        if (user.role === 'Administrator') {
            return res.status(403).json({
                status: 'error',
                message: 'Cannot delete another Administrator account'
            });
        }

        const deletedUsername = user.username;
        const deletedRole = user.role;
        const deletedCompanyId = user.companyId;

        // Permanent delete
        await User.findByIdAndDelete(userId);

        res.json({
            status: 'success',
            message: `${deletedRole} '${deletedUsername}' has been permanently deleted`,
            data: {
                deletedUser: {
                    id: userId,
                    username: deletedUsername,
                    role: deletedRole,
                    companyId: deletedCompanyId
                }
            }
        });
    } catch (error) {
        console.error('Delete user error:', error);
        res.status(500).json({
            status: 'error',
            message: 'Server error while deleting user'
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
    blockUser,
    unblockUser,
    deleteUser
};
