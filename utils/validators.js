const { body } = require('express-validator');
const User = require('../models/User.model');

const registerValidation = [
    body('username')
    .trim()
    .notEmpty().withMessage('Username is required')
    .isLength({ min: 3 }).withMessage('Username must be at least 3 characters')
    .isLength({ max: 30 }).withMessage('Username cannot exceed 30 characters')
    .custom(async(username) => {
        const existingUser = await User.findOne({ username });
        if (existingUser) {
            throw new Error('Username already exists');
        }
        return true;
    }),

    body('email')
    .trim()
    .notEmpty().withMessage('Email is required')
    .isEmail().withMessage('Please provide a valid email')
    .normalizeEmail()
    .custom(async(email) => {
        const existingUser = await User.findOne({ email });
        if (existingUser) {
            throw new Error('Email already exists');
        }
        return true;
    }),

    body('password')
    .notEmpty().withMessage('Password is required')
    .isLength({ min: 6 }).withMessage('Password must be at least 6 characters')
    .matches(/^(?=.*[a-z])(?=.*[A-Z])(?=.*\d)/)
    .withMessage('Password must contain at least one uppercase letter, one lowercase letter, and one number'),

    body('confirmPassword')
    .notEmpty().withMessage('Please confirm your password')
    .custom((value, { req }) => {
        if (value !== req.body.password) {
            throw new Error('Passwords do not match');
        }
        return true;
    }),

    body('securityQuestions.question1')
    .notEmpty().withMessage('Security question 1 answer is required'),

    body('securityQuestions.question2')
    .notEmpty().withMessage('Security question 2 answer is required')
];

const loginValidation = [
    body('username')
    .trim()
    .notEmpty().withMessage('Username is required'),

    body('password')
    .notEmpty().withMessage('Password is required')
];

const drinkValidation = [
    body('name')
    .trim()
    .notEmpty().withMessage('Drink name is required')
    .isLength({ max: 100 }).withMessage('Drink name cannot exceed 100 characters'),

    body('price')
    .isFloat({ min: 0 }).withMessage('Price must be a positive number'),

    body('category')
    .isIn(['Beer', 'Wine', 'Cocktail', 'Soft Drink', 'Other'])
    .withMessage('Invalid category'),

    body('description')
    .optional()
    .isLength({ max: 500 }).withMessage('Description cannot exceed 500 characters'),

    body('alcoholContent')
    .optional()
    .isFloat({ min: 0, max: 100 }).withMessage('Alcohol content must be between 0 and 100'),

    body('volume')
    .optional()
    .isFloat({ min: 0 }).withMessage('Volume cannot be negative'),

    body('unit')
    .optional()
    .isIn(['ml', 'cl', 'l', 'oz'])
    .withMessage('Invalid unit')
];

const orderValidation = [
    body('items')
    .isArray({ min: 1 }).withMessage('Order must have at least one item'),

    body('items.*.drink')
    .notEmpty().withMessage('Drink ID is required'),

    body('items.*.quantity')
    .isInt({ min: 1 }).withMessage('Quantity must be at least 1'),

    body('amountPaid')
    .isFloat({ min: 0 }).withMessage('Amount paid cannot be negative'),

    body('customerName')
    .optional()
    .trim()
    .isLength({ max: 100 }).withMessage('Customer name cannot exceed 100 characters'),

    body('customerEmail')
    .optional()
    .isEmail().withMessage('Please provide a valid email'),

    body('paymentMethod')
    .optional()
    .isIn(['cash', 'card', 'mobile', 'other'])
    .withMessage('Invalid payment method'),

    body('notes')
    .optional()
    .isLength({ max: 500 }).withMessage('Notes cannot exceed 500 characters'),

    body('discount')
    .optional()
    .isFloat({ min: 0 }).withMessage('Discount cannot be negative'),

    body('tax')
    .optional()
    .isFloat({ min: 0 }).withMessage('Tax cannot be negative')
];

const passwordResetValidation = [
    body('email')
    .trim()
    .notEmpty().withMessage('Email is required')
    .isEmail().withMessage('Please provide a valid email'),

    body('securityAnswers.question1')
    .notEmpty().withMessage('Security question 1 answer is required'),

    body('securityAnswers.question2')
    .notEmpty().withMessage('Security question 2 answer is required'),

    body('newPassword')
    .notEmpty().withMessage('New password is required')
    .isLength({ min: 6 }).withMessage('Password must be at least 6 characters')
    .matches(/^(?=.*[a-z])(?=.*[A-Z])(?=.*\d)/)
    .withMessage('Password must contain at least one uppercase letter, one lowercase letter, and one number'),

    body('confirmPassword')
    .notEmpty().withMessage('Please confirm your password')
    .custom((value, { req }) => {
        if (value !== req.body.newPassword) {
            throw new Error('Passwords do not match');
        }
        return true;
    })
];

const changePasswordValidation = [
    body('currentPassword')
    .notEmpty().withMessage('Current password is required'),

    body('newPassword')
    .notEmpty().withMessage('New password is required')
    .isLength({ min: 6 }).withMessage('Password must be at least 6 characters')
    .matches(/^(?=.*[a-z])(?=.*[A-Z])(?=.*\d)/)
    .withMessage('Password must contain at least one uppercase letter, one lowercase letter, and one number')
    .custom((value, { req }) => {
        if (value === req.body.currentPassword) {
            throw new Error('New password must be different from current password');
        }
        return true;
    }),

    body('confirmPassword')
    .notEmpty().withMessage('Please confirm your password')
    .custom((value, { req }) => {
        if (value !== req.body.newPassword) {
            throw new Error('Passwords do not match');
        }
        return true;
    })
];

const updateProfileValidation = [
    body('username')
    .optional()
    .trim()
    .isLength({ min: 3 }).withMessage('Username must be at least 3 characters')
    .isLength({ max: 30 }).withMessage('Username cannot exceed 30 characters')
    .custom(async(username, { req }) => {
        const existingUser = await User.findOne({
            username,
            _id: { $ne: req.user._id }
        });
        if (existingUser) {
            throw new Error('Username already exists');
        }
        return true;
    }),

    body('email')
    .optional()
    .trim()
    .isEmail().withMessage('Please provide a valid email')
    .normalizeEmail()
    .custom(async(email, { req }) => {
        const existingUser = await User.findOne({
            email,
            _id: { $ne: req.user._id }
        });
        if (existingUser) {
            throw new Error('Email already exists');
        }
        return true;
    }),

    body('securityQuestions.question1')
    .optional()
    .notEmpty().withMessage('Security question 1 answer is required'),

    body('securityQuestions.question2')
    .optional()
    .notEmpty().withMessage('Security question 2 answer is required')
];

const syncValidation = [
    body('drinks')
    .optional()
    .isArray().withMessage('Drinks must be an array'),

    body('orders')
    .optional()
    .isArray().withMessage('Orders must be an array'),

    body('lastSync')
    .optional()
    .isISO8601().withMessage('Last sync must be a valid date')
];

module.exports = {
    registerValidation,
    loginValidation,
    drinkValidation,
    orderValidation,
    passwordResetValidation,
    changePasswordValidation,
    updateProfileValidation,
    syncValidation
};