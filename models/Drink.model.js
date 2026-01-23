const mongoose = require('mongoose');

const drinkSchema = new mongoose.Schema({
    name: {
        type: String,
        required: [true, 'Drink name is required'],
        trim: true,
        maxlength: [100, 'Drink name cannot exceed 100 characters']
    },
    price: {
        type: Number,
        required: [true, 'Price is required'],
        min: [0, 'Price cannot be negative']
    },
    category: {
        type: String,
        required: [true, 'Category is required'],
        enum: ['Beer', 'Wine', 'Cocktail', 'Soft Drink', 'Other']
    },
    imageUrl: {
        type: String,
        default: 'https://via.placeholder.com/150/667EEA/FFFFFF?text=Drink'
    },
    description: {
        type: String,
        maxlength: [500, 'Description cannot exceed 500 characters']
    },
    isCustom: {
        type: Boolean,
        default: true
    },
    userId: {
        type: mongoose.Schema.Types.ObjectId,
        ref: 'User',
        required: true
    },
    isActive: {
        type: Boolean,
        default: true
    },
    tags: [{
        type: String,
        trim: true
    }],
    alcoholContent: {
        type: Number,
        min: [0, 'Alcohol content cannot be negative'],
        max: [100, 'Alcohol content cannot exceed 100%'],
        default: 0
    },
    volume: {
        type: Number,
        min: [0, 'Volume cannot be negative']
    },
    unit: {
        type: String,
        enum: ['ml', 'cl', 'l', 'oz'],
        default: 'ml'
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
    }
}, {
    timestamps: true,
    toJSON: { virtuals: true },
    toObject: { virtuals: true }
});

// Indexes for faster queries
drinkSchema.index({ name: 1 });
drinkSchema.index({ category: 1 });
drinkSchema.index({ price: 1 });
drinkSchema.index({ userId: 1 });
drinkSchema.index({ localId: 1 }, { sparse: true });
drinkSchema.index({ syncStatus: 1 });

// Virtual for formatted price
drinkSchema.virtual('formattedPrice').get(function() {
    return `${this.price.toFixed(0)} Frs`;
});

// Virtual for display name with price
drinkSchema.virtual('displayName').get(function() {
    return `${this.name} - ${this.formattedPrice}`;
});

// Pre-save middleware
drinkSchema.pre('save', function(next) {
    if (!this.localId) {
        this.localId = `local_${Date.now()}_${Math.random().toString(36).substr(2, 9)}`;
    }
    next();
});

const Drink = mongoose.model('Drink', drinkSchema);

module.exports = Drink;