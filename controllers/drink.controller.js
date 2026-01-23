const Drink = require('../models/Drink.model');
const { paginate, calculateDrinkStats } = require('../utils/helpers');

// @desc    Get all drinks
// @route   GET /api/drinks
// @access  Private
const getDrinks = async(req, res) => {
    try {
        const {
            page = 1,
                limit = 10,
                category,
                search,
                sort = '-createdAt',
                includeInactive = false
        } = req.query;

        // Build query
        const query = { userId: req.user._id };

        // Filter by category
        if (category) {
            query.category = category;
        }

        // Search by name
        if (search) {
            query.name = { $regex: search, $options: 'i' };
        }

        // Only show active drinks by default
        if (!includeInactive) {
            query.isActive = true;
        }

        // Pagination
        const skip = (page - 1) * limit;

        // Get drinks
        const drinks = await Drink.find(query)
            .sort(sort)
            .skip(skip)
            .limit(parseInt(limit))
            .populate('userId', 'username email');

        // Get total count
        const total = await Drink.countDocuments(query);

        // Calculate stats
        const stats = calculateDrinkStats(await Drink.find({ userId: req.user._id, isActive: true }));

        res.json({
            status: 'success',
            data: {
                drinks,
                pagination: {
                    page: parseInt(page),
                    limit: parseInt(limit),
                    total,
                    pages: Math.ceil(total / limit)
                },
                stats
            }
        });
    } catch (error) {
        console.error('Get drinks error:', error);
        res.status(500).json({
            status: 'error',
            message: 'Server error'
        });
    }
};

// @desc    Get drink by ID
// @route   GET /api/drinks/:id
// @access  Private
const getDrinkById = async(req, res) => {
    try {
        const drink = await Drink.findOne({
            _id: req.params.id,
            userId: req.user._id
        }).populate('userId', 'username email');

        if (!drink) {
            return res.status(404).json({
                status: 'error',
                message: 'Drink not found'
            });
        }

        res.json({
            status: 'success',
            data: { drink }
        });
    } catch (error) {
        console.error('Get drink error:', error);
        res.status(500).json({
            status: 'error',
            message: 'Server error'
        });
    }
};

// @desc    Create drink
// @route   POST /api/drinks
// @access  Private
const createDrink = async(req, res) => {
    try {
        const { name, price, category, imageUrl, description, tags, alcoholContent, volume, unit } = req.body;

        // Check if drink already exists
        const existingDrink = await Drink.findOne({
            name,
            userId: req.user._id
        });

        if (existingDrink) {
            return res.status(400).json({
                status: 'error',
                message: 'Drink with this name already exists'
            });
        }

        // Create drink
        const drink = await Drink.create({
            name,
            price,
            category,
            imageUrl: imageUrl || undefined,
            description,
            userId: req.user._id,
            tags,
            alcoholContent,
            volume,
            unit
        });

        res.status(201).json({
            status: 'success',
            message: 'Drink created successfully',
            data: { drink }
        });
    } catch (error) {
        console.error('Create drink error:', error);
        res.status(500).json({
            status: 'error',
            message: 'Server error'
        });
    }
};

// @desc    Update drink
// @route   PUT /api/drinks/:id
// @access  Private
const updateDrink = async(req, res) => {
    try {
        const { id } = req.params;

        // Find drink
        let drink = await Drink.findOne({
            _id: id,
            userId: req.user._id
        });

        if (!drink) {
            return res.status(404).json({
                status: 'error',
                message: 'Drink not found'
            });
        }

        // Update drink
        drink = await Drink.findByIdAndUpdate(
            id, { $set: req.body }, { new: true, runValidators: true }
        );

        res.json({
            status: 'success',
            message: 'Drink updated successfully',
            data: { drink }
        });
    } catch (error) {
        console.error('Update drink error:', error);
        res.status(500).json({
            status: 'error',
            message: 'Server error'
        });
    }
};

// @desc    Delete drink (soft delete)
// @route   DELETE /api/drinks/:id
// @access  Private
const deleteDrink = async(req, res) => {
    try {
        const { id } = req.params;

        // Find drink
        const drink = await Drink.findOne({
            _id: id,
            userId: req.user._id
        });

        if (!drink) {
            return res.status(404).json({
                status: 'error',
                message: 'Drink not found'
            });
        }

        // Soft delete (set isActive to false)
        drink.isActive = false;
        await drink.save();

        res.json({
            status: 'success',
            message: 'Drink deleted successfully'
        });
    } catch (error) {
        console.error('Delete drink error:', error);
        res.status(500).json({
            status: 'error',
            message: 'Server error'
        });
    }
};

// @desc    Bulk create/update drinks (for sync)
// @route   POST /api/drinks/bulk
// @access  Private
const bulkUpdateDrinks = async(req, res) => {
    try {
        const { drinks } = req.body; // Array of drinks

        const results = {
            created: [],
            updated: [],
            failed: []
        };

        for (const drinkData of drinks) {
            try {
                if (drinkData._id) {
                    // Update existing drink
                    const drink = await Drink.findOneAndUpdate({ _id: drinkData._id, userId: req.user._id },
                        drinkData, { new: true, upsert: false }
                    );

                    if (drink) {
                        results.updated.push(drink._id);
                    } else {
                        results.failed.push({
                            id: drinkData._id,
                            error: 'Drink not found or not owned by user'
                        });
                    }
                } else {
                    // Create new drink
                    const drink = await Drink.create({
                        ...drinkData,
                        userId: req.user._id
                    });
                    results.created.push(drink._id);
                }
            } catch (error) {
                results.failed.push({
                    id: drinkData._id || 'new',
                    error: error.message
                });
            }
        }

        res.json({
            status: 'success',
            message: 'Bulk operation completed',
            data: results
        });
    } catch (error) {
        console.error('Bulk update drinks error:', error);
        res.status(500).json({
            status: 'error',
            message: 'Server error'
        });
    }
};

// @desc    Get drink categories
// @route   GET /api/drinks/categories
// @access  Private
const getCategories = async(req, res) => {
    try {
        const categories = await Drink.distinct('category', {
            userId: req.user._id,
            isActive: true
        });

        res.json({
            status: 'success',
            data: { categories }
        });
    } catch (error) {
        console.error('Get categories error:', error);
        res.status(500).json({
            status: 'error',
            message: 'Server error'
        });
    }
};

// @desc    Get drink statistics
// @route   GET /api/drinks/stats
// @access  Private
const getDrinkStats = async(req, res) => {
    try {
        const stats = calculateDrinkStats(
            await Drink.find({
                userId: req.user._id,
                isActive: true
            })
        );

        // Get category distribution
        const categoryStats = await Drink.aggregate([{
                $match: {
                    userId: req.user._id,
                    isActive: true
                }
            },
            {
                $group: {
                    _id: '$category',
                    count: { $sum: 1 },
                    totalValue: { $sum: '$price' },
                    avgPrice: { $avg: '$price' }
                }
            },
            { $sort: { count: -1 } }
        ]);

        // Get recent drinks
        const recentDrinks = await Drink.find({
                userId: req.user._id,
                isActive: true
            })
            .sort({ createdAt: -1 })
            .limit(5)
            .populate('userId', 'username');

        res.json({
            status: 'success',
            data: {
                overview: stats,
                categories: categoryStats,
                recentDrinks
            }
        });
    } catch (error) {
        console.error('Get drink stats error:', error);
        res.status(500).json({
            status: 'error',
            message: 'Server error'
        });
    }
};

// @desc    Search drinks
// @route   GET /api/drinks/search
// @access  Private
const searchDrinks = async(req, res) => {
    try {
        const { query } = req.query;

        if (!query) {
            return res.status(400).json({
                status: 'error',
                message: 'Search query is required'
            });
        }

        const drinks = await Drink.find({
                userId: req.user._id,
                isActive: true,
                $or: [
                    { name: { $regex: query, $options: 'i' } },
                    { category: { $regex: query, $options: 'i' } },
                    { description: { $regex: query, $options: 'i' } },
                    { tags: { $regex: query, $options: 'i' } }
                ]
            })
            .sort({ name: 1 })
            .limit(20);

        res.json({
            status: 'success',
            data: { drinks }
        });
    } catch (error) {
        console.error('Search drinks error:', error);
        res.status(500).json({
            status: 'error',
            message: 'Server error'
        });
    }
};

module.exports = {
    getDrinks,
    getDrinkById,
    createDrink,
    updateDrink,
    deleteDrink,
    bulkUpdateDrinks,
    getCategories,
    getDrinkStats,
    searchDrinks
};