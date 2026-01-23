module.exports = {
    ROLES: {
        ADMIN: 'Administrator',
        MANAGER: 'Manager',
        STAFF: 'Staff',
        CUSTOMER: 'Customer'
    },

    DRINK_CATEGORIES: ['Beer', 'Wine', 'Cocktail', 'Soft Drink', 'Other'],

    ORDER_STATUS: {
        PENDING: 'pending',
        COMPLETED: 'completed',
        CANCELLED: 'cancelled',
        REFUNDED: 'refunded'
    },

    PAYMENT_METHODS: ['cash', 'card', 'mobile', 'other'],

    DEFAULT_DRINK_IMAGE: 'https://via.placeholder.com/150/667EEA/FFFFFF?text=Drink',

    DEFAULT_PRICES: {
        'Beer': 800,
        'Wine': 3000,
        'Cocktail': 3500,
        'Soft Drink': 700,
        'Other': 1000
    },

    SECURITY_QUESTIONS: [
        "What was your first pet's name?",
        "What city were you born in?",
        "What is your mother's maiden name?",
        "What was the name of your first school?",
        "What is your favorite movie?"
    ],

    PAGINATION: {
        DEFAULT_LIMIT: 10,
        MAX_LIMIT: 100
    },

    SYNC_STATUS: {
        SYNCED: 'synced',
        PENDING: 'pending',
        CONFLICT: 'conflict'
    },

    EMAIL_TEMPLATES: {
        PASSWORD_RESET: 'password_reset',
        WELCOME: 'welcome',
        ORDER_CONFIRMATION: 'order_confirmation',
        PASSWORD_CHANGED: 'password_changed'
    }
};