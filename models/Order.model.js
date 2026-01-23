const mongoose = require('mongoose');

const orderItemSchema = new mongoose.Schema({
    drink: {
        type: mongoose.Schema.Types.ObjectId,
        ref: 'Drink',
        required: true
    },
    drinkName: {
        type: String,
        required: true
    },
    quantity: {
        type: Number,
        required: true,
        min: [1, 'Quantity must be at least 1']
    },
    pricePerUnit: {
        type: Number,
        required: true,
        min: [0, 'Price cannot be negative']
    },
    totalPrice: {
        type: Number,
        required: true,
        min: [0, 'Total price cannot be negative']
    }
}, {
    _id: false
});

const orderSchema = new mongoose.Schema({
    orderNumber: {
        type: String,
        unique: true,
        required: true
    },
    user: {
        type: mongoose.Schema.Types.ObjectId,
        ref: 'User',
        required: true
    },
    customerName: {
        type: String,
        trim: true
    },
    customerEmail: {
        type: String,
        trim: true,
        lowercase: true
    },
    items: [orderItemSchema],
    totalAmount: {
        type: Number,
        required: true,
        min: [0, 'Total amount cannot be negative']
    },
    amountPaid: {
        type: Number,
        required: true,
        min: [0, 'Amount paid cannot be negative']
    },
    balance: {
        type: Number,
        required: true
    },
    paymentMethod: {
        type: String,
        enum: ['cash', 'card', 'mobile', 'other'],
        default: 'cash'
    },
    status: {
        type: String,
        enum: ['pending', 'completed', 'cancelled', 'refunded'],
        default: 'completed'
    },
    notes: {
        type: String,
        maxlength: [500, 'Notes cannot exceed 500 characters']
    },
    receiptPrinted: {
        type: Boolean,
        default: false
    },
    receiptNumber: {
        type: String,
        unique: true
    },
    discount: {
        type: Number,
        min: [0, 'Discount cannot be negative'],
        default: 0
    },
    tax: {
        type: Number,
        min: [0, 'Tax cannot be negative'],
        default: 0
    },
    subtotal: {
        type: Number,
        min: [0, 'Subtotal cannot be negative']
    },
    // For offline sync
    localId: {
        type: String,
        unique: true,
        sparse: true
    },
    lastSynced: {
        type: Date
    },
    syncStatus: {
        type: String,
        enum: ['synced', 'pending', 'conflict'],
        default: 'synced'
    },
    // Email notification
    emailSent: {
        type: Boolean,
        default: false
    }
}, {
    timestamps: true,
    toJSON: { virtuals: true },
    toObject: { virtuals: true }
});

// Generate order number before saving
orderSchema.pre('save', async function(next) {
    if (!this.orderNumber) {
        const date = new Date();
        const year = date.getFullYear();
        const month = String(date.getMonth() + 1).padStart(2, '0');
        const day = String(date.getDate()).padStart(2, '0');
        const random = Math.floor(1000 + Math.random() * 9000);
        this.orderNumber = `ORD-${year}${month}${day}-${random}`;
    }

    if (!this.receiptNumber) {
        this.receiptNumber = `REC-${Date.now()}-${Math.floor(Math.random() * 1000)}`;
    }

    // Calculate subtotal
    this.subtotal = this.items.reduce((sum, item) => sum + item.totalPrice, 0);

    // Calculate balance
    this.balance = this.amountPaid - (this.subtotal - this.discount + this.tax);

    next();
});

// Indexes for faster queries
orderSchema.index({ orderNumber: 1 });
orderSchema.index({ user: 1 });
orderSchema.index({ createdAt: -1 });
orderSchema.index({ status: 1 });
orderSchema.index({ customerName: 1 });
orderSchema.index({ localId: 1 }, { sparse: true });
orderSchema.index({ syncStatus: 1 });

// Virtual for profit
orderSchema.virtual('profit').get(function() {
    return this.subtotal * 0.3; // Assuming 30% profit margin
});

// Virtual for formatted dates
orderSchema.virtual('formattedDate').get(function() {
    return this.createdAt.toLocaleDateString('en-US', {
        year: 'numeric',
        month: 'long',
        day: 'numeric',
        hour: '2-digit',
        minute: '2-digit'
    });
});

const Order = mongoose.model('Order', orderSchema);

module.exports = Order;