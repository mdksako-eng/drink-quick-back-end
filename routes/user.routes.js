const express = require('express');
const router = express.Router();
const userController = require('../controllers/user.controller');
const { protect, authorize } = require('../middleware/auth.middleware');
const { validate } = require('../middleware/validation.middleware');
const validators = require('../utils/validators');

// All routes are protected
router.use(protect);

// User profile routes
router.get('/profile', userController.getProfile);
router.put('/profile', validate(validators.updateProfileValidation), userController.updateProfile);
router.put('/change-password', validate(validators.changePasswordValidation), userController.changePassword);
router.post('/upload-image', userController.uploadImage);

// Admin routes
router.use(authorize('Administrator'));

// Get all users
router.get('/', userController.getAllUsers);

// Get user by ID
router.get('/:id', userController.getUserById);

// Update user (admin)
router.put('/:id', userController.updateUser);

// Delete user
router.delete('/:id', userController.deleteUser);

module.exports = router;