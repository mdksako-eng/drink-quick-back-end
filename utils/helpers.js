const crypto = require('crypto');

// Generate random string
const generateRandomString = (length = 10) => {
    return crypto.randomBytes(length).toString('hex').slice(0, length);
};

// Generate unique ID for local storage
const generateLocalId = () => {
    return `local_${Date.now()}_${Math.random().toString(36).substr(2, 9)}`;
};

// Format currency
const formatCurrency = (amount, currency = 'Frs') => {
    return `${amount.toFixed(0)} ${currency}`;
};

// Generate order number
const generateOrderNumber = () => {
    const date = new Date();
    const year = date.getFullYear();
    const month = String(date.getMonth() + 1).padStart(2, '0');
    const day = String(date.getDate()).padStart(2, '0');
    const random = Math.floor(1000 + Math.random() * 9000);
    return `ORD-${year}${month}${day}-${random}`;
};

// Generate receipt number
const generateReceiptNumber = () => {
    return `REC-${Date.now()}-${Math.floor(Math.random() * 1000)}`;
};

// Calculate age from date
const calculateAge = (birthDate) => {
    const today = new Date();
    const birth = new Date(birthDate);
    let age = today.getFullYear() - birth.getFullYear();
    const monthDiff = today.getMonth() - birth.getMonth();

    if (monthDiff < 0 || (monthDiff === 0 && today.getDate() < birth.getDate())) {
        age--;
    }

    return age;
};

// Pagination helper
const paginate = (model, page = 1, limit = 10, query = {}) => {
    const skip = (page - 1) * limit;

    return model.find(query)
        .skip(skip)
        .limit(limit)
        .sort({ createdAt: -1 });
};

// Calculate drink statistics
const calculateDrinkStats = (drinks) => {
    if (!drinks.length) return null;

    const total = drinks.length;
    const totalValue = drinks.reduce((sum, drink) => sum + drink.price, 0);
    const avgPrice = totalValue / total;
    const maxPrice = Math.max(...drinks.map(d => d.price));
    const minPrice = Math.min(...drinks.map(d => d.price));

    // Category distribution
    const categories = {};
    drinks.forEach(drink => {
        categories[drink.category] = (categories[drink.category] || 0) + 1;
    });

    return {
        total,
        totalValue,
        avgPrice: parseFloat(avgPrice.toFixed(2)),
        maxPrice,
        minPrice,
        categories
    };
};

// Sanitize user data
const sanitizeUser = (user) => {
    const userObj = user.toObject ? user.toObject() : user;
    delete userObj.password;
    delete userObj.refreshToken;
    delete userObj.resetPasswordToken;
    delete userObj.resetPasswordExpire;
    delete userObj.loginAttempts;
    delete userObj.lockUntil;
    delete userObj.__v;
    return userObj;
};

// Generate password reset token
const generateResetToken = () => {
    return crypto.randomBytes(32).toString('hex');
};

// Hash token
const hashToken = (token) => {
    return crypto
        .createHash('sha256')
        .update(token)
        .digest('hex');
};

// Validate email
const isValidEmail = (email) => {
    const emailRegex = /^\w+([.-]?\w+)*@\w+([.-]?\w+)*(\.\w{2,3})+$/;
    return emailRegex.test(email);
};

// Validate password strength
const validatePasswordStrength = (password) => {
    const minLength = 6;
    const hasUpperCase = /[A-Z]/.test(password);
    const hasLowerCase = /[a-z]/.test(password);
    const hasNumbers = /\d/.test(password);
    const hasSpecialChar = /[!@#$%^&*(),.?":{}|<>]/.test(password);

    const strength = [
        password.length >= minLength,
        hasUpperCase,
        hasLowerCase,
        hasNumbers,
        hasSpecialChar
    ].filter(Boolean).length;

    let message = '';
    let level = 'weak';

    if (strength <= 2) {
        message = 'Weak password';
        level = 'weak';
    } else if (strength <= 4) {
        message = 'Medium password';
        level = 'medium';
    } else {
        message = 'Strong password';
        level = 'strong';
    }

    return { isValid: password.length >= minLength, message, level };
};

// Format date
const formatDate = (date, format = 'DD/MM/YYYY HH:mm') => {
    const d = new Date(date);
    const day = String(d.getDate()).padStart(2, '0');
    const month = String(d.getMonth() + 1).padStart(2, '0');
    const year = d.getFullYear();
    const hours = String(d.getHours()).padStart(2, '0');
    const minutes = String(d.getMinutes()).padStart(2, '0');

    switch (format) {
        case 'DD/MM/YYYY HH:mm':
            return `${day}/${month}/${year} ${hours}:${minutes}`;
        case 'YYYY-MM-DD':
            return `${year}-${month}-${day}`;
        case 'MMM DD, YYYY':
            const months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
            return `${months[d.getMonth()]} ${day}, ${year}`;
        default:
            return d.toISOString();
    }
};

module.exports = {
    generateRandomString,
    generateLocalId,
    formatCurrency,
    generateOrderNumber,
    generateReceiptNumber,
    calculateAge,
    paginate,
    calculateDrinkStats,
    sanitizeUser,
    generateResetToken,
    hashToken,
    isValidEmail,
    validatePasswordStrength,
    formatDate
};