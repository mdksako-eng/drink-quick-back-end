const mongoose = require('mongoose');
const bcrypt = require('bcryptjs');
const crypto = require('crypto');

const userSchema = new mongoose.Schema({
    username: {
        type: String,
        required: [true, 'Username is required'],
        unique: true,
        trim: true,
        minlength: [3, 'Username must be at least 3 characters'],
        maxlength: [30, 'Username cannot exceed 30 characters']
    },
    email: {
        type: String,
        required: [true, 'Email is required'],
        unique: true,
        lowercase: true,
        trim: true,
        match: [/^\w+([.-]?\w+)*@\w+([.-]?\w+)*(\.\w{2,3})+$/, 'Please provide a valid email']
    },
    password: {
        type: String,
        required: [true, 'Password is required'],
        minlength: [6, 'Password must be at least 6 characters'],
        select: false
    },
    role: {
        type: String,
        enum: ['Administrator', 'Manager', 'Staff', 'Customer'],
        default: 'Customer'
    },
    securityQuestions: {
        question1: {
            type: String,
            required: [true, 'Security question 1 answer is required']
        },
        question2: {
            type: String,
            required: [true, 'Security question 2 answer is required']
        }
    },
    profileImage: {
        type: String,
        default: ''
    },
    isActive: {
        type: Boolean,
        default: true
    },
    emailVerified: {
        type: Boolean,
        default: false
    },
    lastLogin: {
        type: Date
    },
    refreshToken: {
        type: String,
        select: false
    },
    // Password reset fields
    resetPasswordToken: {
        type: String,
        select: false
    },
    resetPasswordExpire: {
        type: Date,
        select: false
    },
    // Login attempt tracking
    loginAttempts: {
        type: Number,
        default: 0,
        select: false
    },
    lockUntil: {
        type: Date,
        select: false
    }
}, {
    timestamps: true,
    toJSON: { virtuals: true },
    toObject: { virtuals: true }
});

// Virtual for full name
userSchema.virtual('fullName').get(function() {
    return this.username;
});

// Hash password before saving
userSchema.pre('save', async function(next) {
    if (!this.isModified('password')) return next();

    try {
        const salt = await bcrypt.genSalt(10);
        this.password = await bcrypt.hash(this.password, salt);
        next();
    } catch (error) {
        next(error);
    }
});

// Compare password method
userSchema.methods.comparePassword = async function(candidatePassword) {
    return await bcrypt.compare(candidatePassword, this.password);
};

// Generate password reset token
userSchema.methods.generatePasswordResetToken = function() {
    // Generate token
    const resetToken = crypto.randomBytes(32).toString('hex');

    // Hash token and set to resetPasswordToken field
    this.resetPasswordToken = crypto
        .createHash('sha256')
        .update(resetToken)
        .digest('hex');

    // Set expire time (1 hour)
    this.resetPasswordExpire = Date.now() + 3600000;

    return resetToken;
};

// Check if account is locked
userSchema.methods.isLocked = function() {
    return !!(this.lockUntil && this.lockUntil > Date.now());
};

// Increment login attempts
userSchema.methods.incrementLoginAttempts = async function() {
    // If we have a previous lock that has expired, restart at 1
    if (this.lockUntil && this.lockUntil < Date.now()) {
        this.loginAttempts = 1;
        this.lockUntil = undefined;
        return await this.save();
    }

    // Otherwise, increment
    this.loginAttempts += 1;

    // Lock the account if we've reached max attempts and it's not locked already
    if (this.loginAttempts >= 5 && !this.isLocked()) {
        this.lockUntil = Date.now() + 15 * 60 * 1000; // 15 minutes
    }

    return await this.save();
};

// Reset login attempts on successful login
userSchema.methods.resetLoginAttempts = async function() {
    this.loginAttempts = 0;
    this.lockUntil = undefined;
    return await this.save();
};

// Update last login
userSchema.methods.updateLastLogin = async function() {
    this.lastLogin = Date.now();
    await this.save();
};

// Static method to find by reset token
userSchema.statics.findByResetToken = function(token) {
    const hashedToken = crypto
        .createHash('sha256')
        .update(token)
        .digest('hex');

    return this.findOne({
        resetPasswordToken: hashedToken,
        resetPasswordExpire: { $gt: Date.now() }
    }).select('+resetPasswordToken +resetPasswordExpire');
};

const User = mongoose.model('User', userSchema);

module.exports = User;