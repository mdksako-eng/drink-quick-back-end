const User = require('../models/User.model');
const { sanitizeUser } = require('../utils/helpers');
const emailService = require('../utils/email.service');

// @desc    Get user profile
// @route   GET /api/users/profile
// @access  Private
const getProfile = async(req, res) => {
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
        console.error('Get profile error:', error);
        res.status(500).json({
            status: 'error',
            message: 'Server error'
        });
    }
};

// @desc    Update user profile
// @route   PUT /api/users/profile
// @access  Private
const updateProfile = async(req, res) => {
    try {
        const { username, email, securityQuestions } = req.body;

        // Check if username or email already exists
        if (username || email) {
            const existingUser = await User.findOne({
                $and: [
                    { _id: { $ne: req.user._id } },
                    { $or: [{ username }, { email }] }
                ]
            });

            if (existingUser) {
                return res.status(400).json({
                    status: 'error',
                    message: 'Username or email already exists'
                });
            }
        }

        // Update user
        const user = await User.findByIdAndUpdate(
            req.user._id, { $set: req.body }, { new: true, runValidators: true }
        );

        const userData = sanitizeUser(user);

        res.json({
            status: 'success',
            message: 'Profile updated successfully',
            data: { user: userData }
        });
    } catch (error) {
        console.error('Update profile error:', error);
        res.status(500).json({
            status: 'error',
            message: 'Server error'
        });
    }
};

// @desc    Upload profile image
// @route   POST /api/users/upload-image
// @access  Private
const uploadImage = async(req, res) => {
    try {
        // In a real implementation, you would upload to cloud storage
        // For now, accept a URL
        const { imageUrl } = req.body;

        if (!imageUrl) {
            return res.status(400).json({
                status: 'error',
                message: 'Image URL is required'
            });
        }

        const user = await User.findByIdAndUpdate(
            req.user._id, { profileImage: imageUrl }, { new: true }
        );

        const userData = sanitizeUser(user);

        res.json({
            status: 'success',
            message: 'Profile image updated successfully',
            data: { user: userData }
        });
    } catch (error) {
        console.error('Upload image error:', error);
        res.status(500).json({
            status: 'error',
            message: 'Server error'
        });
    }
};

// @desc    Get all users (admin only)
// @route   GET /api/users
// @access  Private/Admin
const getAllUsers = async(req, res) => {
    try {
        const { page = 1, limit = 10, role, search } = req.query;

        // Build query
        const query = {};

        if (role) {
            query.role = role;
        }

        if (search) {
            query.$or = [
                { username: { $regex: search, $options: 'i' } },
                { email: { $regex: search, $options: 'i' } }
            ];
        }

        // Pagination
        const skip = (page - 1) * limit;

        // Get users
        const users = await User.find(query)
            .sort({ createdAt: -1 })
            .skip(skip)
            .limit(parseInt(limit))
            .select('-password -refreshToken -resetPasswordToken -resetPasswordExpire');

        // Get total count
        const total = await User.countDocuments(query);

        // Get user statistics
        const userStats = await User.aggregate([{
            $group: {
                _id: '$role',
                count: { $sum: 1 }
            }
        }]);

        // Format stats
        const formattedStats = {};
        userStats.forEach(stat => {
            formattedStats[stat._id] = stat.count;
        });

        res.json({
            status: 'success',
            data: {
                users,
                pagination: {
                    page: parseInt(page),
                    limit: parseInt(limit),
                    total,
                    pages: Math.ceil(total / limit)
                },
                stats: formattedStats
            }
        });
    } catch (error) {
        console.error('Get all users error:', error);
        res.status(500).json({
            status: 'error',
            message: 'Server error'
        });
    }
};

// @desc    Get user by ID (admin only)
// @route   GET /api/users/:id
// @access  Private/Admin
const getUserById = async(req, res) => {
    try {
        const user = await User.findById(req.params.id).select('-password -refreshToken -resetPasswordToken -resetPasswordExpire');

        if (!user) {
            return res.status(404).json({
                status: 'error',
                message: 'User not found'
            });
        }

        res.json({
            status: 'success',
            data: { user }
        });
    } catch (error) {
        console.error('Get user by ID error:', error);
        res.status(500).json({
            status: 'error',
            message: 'Server error'
        });
    }
};

// @desc    Update user (admin only)
// @route   PUT /api/users/:id
// @access  Private/Admin
const updateUser = async(req, res) => {
    try {
        const { id } = req.params;

        // Check if user exists
        const user = await User.findById(id);

        if (!user) {
            return res.status(404).json({
                status: 'error',
                message: 'User not found'
            });
        }

        // Update user
        const updatedUser = await User.findByIdAndUpdate(
            id, { $set: req.body }, { new: true, runValidators: true }
        ).select('-password -refreshToken -resetPasswordToken -resetPasswordExpire');

        res.json({
            status: 'success',
            message: 'User updated successfully',
            data: { user: updatedUser }
        });
    } catch (error) {
        console.error('Update user error:', error);
        res.status(500).json({
            status: 'error',
            message: 'Server error'
        });
    }
};

// @desc    Delete user (admin only)
// @route   DELETE /api/users/:id
// @access  Private/Admin
const deleteUser = async(req, res) => {
    try {
        const { id } = req.params;

        // Check if user exists
        const user = await User.findById(id);

        if (!user) {
            return res.status(404).json({
                status: 'error',
                message: 'User not found'
            });
        }

        // Prevent deleting own account
        if (id === req.user._id.toString()) {
            return res.status(400).json({
                status: 'error',
                message: 'Cannot delete your own account'
            });
        }

        // Soft delete (set isActive to false)
        user.isActive = false;
        await user.save();

        res.json({
            status: 'success',
            message: 'User deactivated successfully'
        });
    } catch (error) {
        console.error('Delete user error:', error);
        res.status(500).json({
            status: 'error',
            message: 'Server error'
        });
    }
};

// @desc    Reactivate user (admin only)
// @route   POST /api/users/:id/reactivate
// @access  Private/Admin
const reactivateUser = async(req, res) => {
    try {
        const { id } = req.params;

        const user = await User.findById(id);

        if (!user) {
            return res.status(404).json({
                status: 'error',
                message: 'User not found'
            });
        }

        user.isActive = true;
        await user.save();

        res.json({
            status: 'success',
            message: 'User reactivated successfully'
        });
    } catch (error) {
        console.error('Reactivate user error:', error);
        res.status(500).json({
            status: 'error',
            message: 'Server error'
        });
    }
};

module.exports = {
    getProfile,
    updateProfile,
    uploadImage,
    getAllUsers,
    getUserById,
    updateUser,
    deleteUser,
    reactivateUser
};