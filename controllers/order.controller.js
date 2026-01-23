const Order = require('../models/Order.model');
const Drink = require('../models/Drink.model');
const User = require('../models/User.model');
const { sendOrderConfirmationEmail } = require('../utils/email.service');
const { formatCurrency } = require('../utils/helpers');

// @desc    Create new order
// @route   POST /api/orders
// @access  Private
const createOrder = async(req, res) => {
    try {
        const { items, amountPaid, customerName, customerEmail, paymentMethod, notes, discount, tax } = req.body;

        // Validate items
        const orderItems = [];
        let totalAmount = 0;

        for (const item of items) {
            const drink = await Drink.findById(item.drink);

            if (!drink) {
                return res.status(404).json({
                    status: 'error',
                    message: `Drink with ID ${item.drink} not found`
                });
            }

            const itemTotal = drink.price * item.quantity;
            totalAmount += itemTotal;

            orderItems.push({
                drink: drink._id,
                drinkName: drink.name,
                quantity: item.quantity,
                pricePerUnit: drink.price,
                totalPrice: itemTotal
            });
        }

        // Apply discount if any
        const finalAmount = totalAmount - (discount || 0) + (tax || 0);

        // Check if payment is sufficient
        if (amountPaid < finalAmount) {
            return res.status(400).json({
                status: 'error',
                message: `Insufficient payment. Required: ${finalAmount}, Paid: ${amountPaid}`
            });
        }

        // Create order
        const order = await Order.create({
            user: req.user._id,
            customerName: customerName || req.user.username,
            customerEmail: customerEmail || req.user.email,
            items: orderItems,
            totalAmount: finalAmount,
            amountPaid,
            balance: amountPaid - finalAmount,
            paymentMethod: paymentMethod || 'cash',
            notes,
            discount: discount || 0,
            tax: tax || 0,
            subtotal: totalAmount
        });

        // Populate drink details
        await order.populate('items.drink', 'name price imageUrl category');

        // Send email notification if customer email provided
        if (customerEmail) {
            try {
                await sendOrderConfirmationEmail(req.user, order);
                order.emailSent = true;
                await order.save();
            } catch (emailError) {
                console.error('Failed to send email:', emailError);
                // Continue without failing the order
            }
        }

        res.status(201).json({
            status: 'success',
            message: 'Order created successfully',
            data: { order }
        });
    } catch (error) {
        console.error('Create order error:', error);
        res.status(500).json({
            status: 'error',
            message: 'Server error'
        });
    }
};

// @desc    Get all orders
// @route   GET /api/orders
// @access  Private
const getOrders = async(req, res) => {
    try {
        const { page = 1, limit = 10, status, startDate, endDate, sort = '-createdAt' } = req.query;

        // Build query
        const query = { user: req.user._id };

        // Filter by status
        if (status) {
            query.status = status;
        }

        // Filter by date range
        if (startDate || endDate) {
            query.createdAt = {};
            if (startDate) query.createdAt.$gte = new Date(startDate);
            if (endDate) query.createdAt.$lte = new Date(endDate);
        }

        // Pagination
        const skip = (page - 1) * limit;

        // Get orders
        const orders = await Order.find(query)
            .sort(sort)
            .skip(skip)
            .limit(parseInt(limit))
            .populate('user', 'username email')
            .populate('items.drink', 'name price category');

        // Get total count
        const total = await Order.countDocuments(query);

        // Calculate total sales
        const salesStats = await Order.aggregate([
            { $match: query },
            {
                $group: {
                    _id: null,
                    totalOrders: { $sum: 1 },
                    totalRevenue: { $sum: '$totalAmount' },
                    totalProfit: { $sum: { $multiply: ['$totalAmount', 0.3] } }, // 30% profit assumption
                    avgOrderValue: { $avg: '$totalAmount' }
                }
            }
        ]);

        res.json({
            status: 'success',
            data: {
                orders,
                pagination: {
                    page: parseInt(page),
                    limit: parseInt(limit),
                    total,
                    pages: Math.ceil(total / limit)
                },
                stats: salesStats[0] || {
                    totalOrders: 0,
                    totalRevenue: 0,
                    totalProfit: 0,
                    avgOrderValue: 0
                }
            }
        });
    } catch (error) {
        console.error('Get orders error:', error);
        res.status(500).json({
            status: 'error',
            message: 'Server error'
        });
    }
};

// @desc    Get order by ID
// @route   GET /api/orders/:id
// @access  Private
const getOrderById = async(req, res) => {
    try {
        const order = await Order.findById(req.params.id)
            .populate('user', 'username email')
            .populate('items.drink', 'name price category imageUrl');

        if (!order) {
            return res.status(404).json({
                status: 'error',
                message: 'Order not found'
            });
        }

        // Check if user owns the order
        if (order.user._id.toString() !== req.user._id.toString() && req.user.role !== 'Administrator') {
            return res.status(403).json({
                status: 'error',
                message: 'Not authorized to view this order'
            });
        }

        res.json({
            status: 'success',
            data: { order }
        });
    } catch (error) {
        console.error('Get order error:', error);
        res.status(500).json({
            status: 'error',
            message: 'Server error'
        });
    }
};

// @desc    Update order
// @route   PUT /api/orders/:id
// @access  Private
const updateOrder = async(req, res) => {
    try {
        const { id } = req.params;

        // Find order
        let order = await Order.findById(id);

        if (!order) {
            return res.status(404).json({
                status: 'error',
                message: 'Order not found'
            });
        }

        // Check if user owns the order
        if (order.user.toString() !== req.user._id.toString() && req.user.role !== 'Administrator') {
            return res.status(403).json({
                status: 'error',
                message: 'Not authorized to update this order'
            });
        }

        // Only allow certain updates
        const allowedUpdates = ['status', 'notes', 'receiptPrinted'];
        const updates = {};

        allowedUpdates.forEach(field => {
            if (req.body[field] !== undefined) {
                updates[field] = req.body[field];
            }
        });

        // Update order
        order = await Order.findByIdAndUpdate(
            id, { $set: updates }, { new: true, runValidators: true }
        );

        res.json({
            status: 'success',
            message: 'Order updated successfully',
            data: { order }
        });
    } catch (error) {
        console.error('Update order error:', error);
        res.status(500).json({
            status: 'error',
            message: 'Server error'
        });
    }
};

// @desc    Delete order (admin only)
// @route   DELETE /api/orders/:id
// @access  Private (Admin only)
const deleteOrder = async(req, res) => {
    try {
        const { id } = req.params;

        // Find order
        const order = await Order.findById(id);

        if (!order) {
            return res.status(404).json({
                status: 'error',
                message: 'Order not found'
            });
        }

        // Only admin can delete orders
        if (req.user.role !== 'Administrator') {
            return res.status(403).json({
                status: 'error',
                message: 'Not authorized to delete orders'
            });
        }

        // Delete order
        await Order.findByIdAndDelete(id);

        res.json({
            status: 'success',
            message: 'Order deleted successfully'
        });
    } catch (error) {
        console.error('Delete order error:', error);
        res.status(500).json({
            status: 'error',
            message: 'Server error'
        });
    }
};

// @desc    Get order statistics
// @route   GET /api/orders/stats
// @access  Private
const getOrderStats = async(req, res) => {
    try {
        const userId = req.user.role === 'Administrator' ? null : req.user._id;
        const query = userId ? { user: userId } : {};

        // Today's date
        const today = new Date();
        today.setHours(0, 0, 0, 0);

        // This week
        const weekStart = new Date(today);
        weekStart.setDate(weekStart.getDate() - weekStart.getDay());

        // This month
        const monthStart = new Date(today.getFullYear(), today.getMonth(), 1);

        // Get overall stats
        const overallStats = await Order.aggregate([
            { $match: query },
            {
                $group: {
                    _id: null,
                    totalOrders: { $sum: 1 },
                    totalRevenue: { $sum: '$totalAmount' },
                    totalItems: { $sum: { $sum: '$items.quantity' } },
                    avgOrderValue: { $avg: '$totalAmount' }
                }
            }
        ]);

        // Get today's stats
        const todayStats = await Order.aggregate([{
                $match: {
                    ...query,
                    createdAt: { $gte: today }
                }
            },
            {
                $group: {
                    _id: null,
                    totalOrders: { $sum: 1 },
                    totalRevenue: { $sum: '$totalAmount' }
                }
            }
        ]);

        // Get weekly stats
        const weeklyStats = await Order.aggregate([{
                $match: {
                    ...query,
                    createdAt: { $gte: weekStart }
                }
            },
            {
                $group: {
                    _id: null,
                    totalOrders: { $sum: 1 },
                    totalRevenue: { $sum: '$totalAmount' }
                }
            }
        ]);

        // Get monthly stats
        const monthlyStats = await Order.aggregate([{
                $match: {
                    ...query,
                    createdAt: { $gte: monthStart }
                }
            },
            {
                $group: {
                    _id: null,
                    totalOrders: { $sum: 1 },
                    totalRevenue: { $sum: '$totalAmount' }
                }
            }
        ]);

        // Get popular drinks
        const popularDrinks = await Order.aggregate([
            { $match: query },
            { $unwind: '$items' },
            {
                $group: {
                    _id: '$items.drinkName',
                    totalQuantity: { $sum: '$items.quantity' },
                    totalRevenue: { $sum: '$items.totalPrice' }
                }
            },
            { $sort: { totalQuantity: -1 } },
            { $limit: 10 }
        ]);

        // Get recent orders
        const recentOrders = await Order.find(query)
            .sort({ createdAt: -1 })
            .limit(5)
            .populate('user', 'username')
            .select('orderNumber totalAmount createdAt status');

        res.json({
            status: 'success',
            data: {
                overall: overallStats[0] || {
                    totalOrders: 0,
                    totalRevenue: 0,
                    totalItems: 0,
                    avgOrderValue: 0
                },
                today: todayStats[0] || { totalOrders: 0, totalRevenue: 0 },
                weekly: weeklyStats[0] || { totalOrders: 0, totalRevenue: 0 },
                monthly: monthlyStats[0] || { totalOrders: 0, totalRevenue: 0 },
                popularDrinks,
                recentOrders
            }
        });
    } catch (error) {
        console.error('Get order stats error:', error);
        res.status(500).json({
            status: 'error',
            message: 'Server error'
        });
    }
};

// @desc    Generate invoice PDF
// @route   POST /api/orders/:id/invoice
// @access  Private
const generateInvoice = async(req, res) => {
    try {
        const { id } = req.params;

        const order = await Order.findById(id)
            .populate('user', 'username email')
            .populate('items.drink', 'name price category');

        if (!order) {
            return res.status(404).json({
                status: 'error',
                message: 'Order not found'
            });
        }

        // Check if user owns the order
        if (order.user._id.toString() !== req.user._id.toString() && req.user.role !== 'Administrator') {
            return res.status(403).json({
                status: 'error',
                message: 'Not authorized to generate invoice for this order'
            });
        }

        // Mark as printed
        order.receiptPrinted = true;
        await order.save();

        // For now, return order data
        // In a real implementation, you would generate a PDF here
        res.json({
            status: 'success',
            message: 'Invoice generated successfully',
            data: {
                order,
                invoiceData: {
                    invoiceNumber: order.receiptNumber,
                    date: order.createdAt,
                    customer: order.customerName || order.user.username,
                    items: order.items,
                    subtotal: order.subtotal,
                    discount: order.discount,
                    tax: order.tax,
                    total: order.totalAmount,
                    amountPaid: order.amountPaid,
                    balance: order.balance,
                    paymentMethod: order.paymentMethod
                }
            }
        });
    } catch (error) {
        console.error('Generate invoice error:', error);
        res.status(500).json({
            status: 'error',
            message: 'Server error'
        });
    }
};

// @desc    Send order confirmation email
// @route   POST /api/orders/:id/send-email
// @access  Private
const sendOrderEmail = async(req, res) => {
    try {
        const { id } = req.params;

        const order = await Order.findById(id)
            .populate('user', 'username email');

        if (!order) {
            return res.status(404).json({
                status: 'error',
                message: 'Order not found'
            });
        }

        // Check if user owns the order
        if (order.user._id.toString() !== req.user._id.toString() && req.user.role !== 'Administrator') {
            return res.status(403).json({
                status: 'error',
                message: 'Not authorized to send email for this order'
            });
        }

        // Send email
        await sendOrderConfirmationEmail(order.user, order);

        // Update order
        order.emailSent = true;
        await order.save();

        res.json({
            status: 'success',
            message: 'Order confirmation email sent successfully'
        });
    } catch (error) {
        console.error('Send order email error:', error);
        res.status(500).json({
            status: 'error',
            message: 'Failed to send email'
        });
    }
};

// @desc    Get orders by date range
// @route   GET /api/orders/filter/date
// @access  Private
const getOrdersByDateRange = async(req, res) => {
    try {
        const { startDate, endDate } = req.query;

        if (!startDate || !endDate) {
            return res.status(400).json({
                status: 'error',
                message: 'startDate and endDate are required'
            });
        }

        const query = {
            user: req.user._id,
            createdAt: {
                $gte: new Date(startDate),
                $lte: new Date(endDate)
            }
        };

        const orders = await Order.find(query)
            .sort({ createdAt: -1 })
            .populate('items.drink', 'name category');

        // Calculate summary
        const summary = await Order.aggregate([
            { $match: query },
            {
                $group: {
                    _id: null,
                    totalOrders: { $sum: 1 },
                    totalRevenue: { $sum: '$totalAmount' },
                    avgOrderValue: { $avg: '$totalAmount' }
                }
            }
        ]);

        res.json({
            status: 'success',
            data: {
                orders,
                summary: summary[0] || {
                    totalOrders: 0,
                    totalRevenue: 0,
                    avgOrderValue: 0
                }
            }
        });
    } catch (error) {
        console.error('Get orders by date range error:', error);
        res.status(500).json({
            status: 'error',
            message: 'Server error'
        });
    }
};

// @desc    Get orders by status
// @route   GET /api/orders/filter/status/:status
// @access  Private
const getOrdersByStatus = async(req, res) => {
    try {
        const { status } = req.params;

        const validStatuses = ['pending', 'completed', 'cancelled', 'refunded'];
        if (!validStatuses.includes(status)) {
            return res.status(400).json({
                status: 'error',
                message: `Invalid status. Must be one of: ${validStatuses.join(', ')}`
            });
        }

        const query = {
            user: req.user._id,
            status: status
        };

        const orders = await Order.find(query)
            .sort({ createdAt: -1 })
            .populate('items.drink', 'name price');

        res.json({
            status: 'success',
            data: {
                orders,
                count: orders.length
            }
        });
    } catch (error) {
        console.error('Get orders by status error:', error);
        res.status(500).json({
            status: 'error',
            message: 'Server error'
        });
    }
};

// @desc    Get dashboard summary
// @route   GET /api/orders/dashboard/summary
// @access  Private
const getDashboardSummary = async(req, res) => {
    try {
        const userId = req.user.role === 'Administrator' ? null : req.user._id;
        const query = userId ? { user: userId } : {};

        // Today
        const today = new Date();
        today.setHours(0, 0, 0, 0);

        // Last 7 days
        const last7Days = new Date();
        last7Days.setDate(last7Days.getDate() - 7);

        // This month
        const thisMonth = new Date(today.getFullYear(), today.getMonth(), 1);

        // Get today's stats
        const todayStats = await Order.aggregate([{
                $match: {
                    ...query,
                    createdAt: { $gte: today }
                }
            },
            {
                $group: {
                    _id: null,
                    orders: { $sum: 1 },
                    revenue: { $sum: '$totalAmount' }
                }
            }
        ]);

        // Get last 7 days stats
        const last7DaysStats = await Order.aggregate([{
                $match: {
                    ...query,
                    createdAt: { $gte: last7Days }
                }
            },
            {
                $group: {
                    _id: null,
                    orders: { $sum: 1 },
                    revenue: { $sum: '$totalAmount' }
                }
            }
        ]);

        // Get this month stats
        const thisMonthStats = await Order.aggregate([{
                $match: {
                    ...query,
                    createdAt: { $gte: thisMonth }
                }
            },
            {
                $group: {
                    _id: null,
                    orders: { $sum: 1 },
                    revenue: { $sum: '$totalAmount' }
                }
            }
        ]);

        // Get top selling drinks
        const topDrinks = await Order.aggregate([
            { $match: query },
            { $unwind: '$items' },
            {
                $group: {
                    _id: '$items.drink',
                    name: { $first: '$items.drinkName' },
                    quantity: { $sum: '$items.quantity' },
                    revenue: { $sum: '$items.totalPrice' }
                }
            },
            { $sort: { quantity: -1 } },
            { $limit: 5 }
        ]);

        // Get recent orders
        const recentOrders = await Order.find(query)
            .sort({ createdAt: -1 })
            .limit(5)
            .populate('user', 'username')
            .select('orderNumber totalAmount status createdAt');

        res.json({
            status: 'success',
            data: {
                today: todayStats[0] || { orders: 0, revenue: 0 },
                last7Days: last7DaysStats[0] || { orders: 0, revenue: 0 },
                thisMonth: thisMonthStats[0] || { orders: 0, revenue: 0 },
                topDrinks,
                recentOrders
            }
        });
    } catch (error) {
        console.error('Get dashboard summary error:', error);
        res.status(500).json({
            status: 'error',
            message: 'Server error'
        });
    }
};

// ====================
// OFFLINE SYNC METHODS
// ====================

// @desc    Bulk sync orders from offline
// @route   POST /api/orders/sync/bulk
// @access  Private
const syncBulkOrders = async(req, res) => {
    try {
        const { orders } = req.body; // Array of orders with localId

        if (!Array.isArray(orders)) {
            return res.status(400).json({
                status: 'error',
                message: 'orders must be an array'
            });
        }

        const results = {
            created: [],
            updated: [],
            conflicts: [],
            errors: []
        };

        for (const orderData of orders) {
            try {
                // Check if order already exists by localId or orderNumber
                const existingOrder = await Order.findOne({
                    $or: [
                        { localId: orderData.localId },
                        { orderNumber: orderData.orderNumber }
                    ]
                });

                if (existingOrder) {
                    // Check for conflicts
                    if (existingOrder.updatedAt > new Date(orderData.updatedAt)) {
                        // Server has newer version - conflict
                        results.conflicts.push({
                            localId: orderData.localId,
                            serverId: existingOrder._id,
                            conflict: 'server_newer',
                            serverData: existingOrder
                        });
                    } else {
                        // Update order with client data
                        const updatedOrder = await Order.findByIdAndUpdate(
                            existingOrder._id, {
                                ...orderData,
                                user: req.user._id,
                                lastSynced: new Date(),
                                syncStatus: 'synced'
                            }, { new: true }
                        );

                        results.updated.push({
                            localId: orderData.localId,
                            serverId: updatedOrder._id
                        });
                    }
                } else {
                    // Create new order
                    const newOrder = await Order.create({
                        ...orderData,
                        user: req.user._id,
                        lastSynced: new Date(),
                        syncStatus: 'synced'
                    });

                    results.created.push({
                        localId: orderData.localId,
                        serverId: newOrder._id
                    });
                }
            } catch (error) {
                results.errors.push({
                    localId: orderData.localId,
                    error: error.message
                });
            }
        }

        res.json({
            status: 'success',
            message: 'Orders synced successfully',
            data: results
        });
    } catch (error) {
        console.error('Bulk sync orders error:', error);
        res.status(500).json({
            status: 'error',
            message: 'Server error'
        });
    }
};

// @desc    Get pending sync orders
// @route   GET /api/orders/sync/pending
// @access  Private
const getPendingSyncOrders = async(req, res) => {
    try {
        const pendingOrders = await Order.find({
            user: req.user._id,
            syncStatus: 'pending'
        });

        res.json({
            status: 'success',
            data: {
                orders: pendingOrders,
                count: pendingOrders.length
            }
        });
    } catch (error) {
        console.error('Get pending sync orders error:', error);
        res.status(500).json({
            status: 'error',
            message: 'Server error'
        });
    }
};

// @desc    Mark orders as synced
// @route   POST /api/orders/sync/mark-synced
// @access  Private
const markOrdersAsSynced = async(req, res) => {
    try {
        const { orderIds } = req.body;

        if (!Array.isArray(orderIds)) {
            return res.status(400).json({
                status: 'error',
                message: 'orderIds must be an array'
            });
        }

        const result = await Order.updateMany({
            _id: { $in: orderIds },
            user: req.user._id
        }, {
            $set: {
                syncStatus: 'synced',
                lastSynced: new Date()
            }
        });

        res.json({
            status: 'success',
            message: `${result.modifiedCount} orders marked as synced`,
            data: result
        });
    } catch (error) {
        console.error('Mark orders as synced error:', error);
        res.status(500).json({
            status: 'error',
            message: 'Server error'
        });
    }
};

// @desc    Resolve sync conflicts
// @route   POST /api/orders/sync/resolve-conflicts
// @access  Private
const resolveSyncConflicts = async(req, res) => {
    try {
        const { resolutions } = req.body; // Array of { orderId, resolution, data }

        if (!Array.isArray(resolutions)) {
            return res.status(400).json({
                status: 'error',
                message: 'resolutions must be an array'
            });
        }

        const results = [];

        for (const resolution of resolutions) {
            try {
                const { orderId, resolution: action, data } = resolution;

                const order = await Order.findOne({
                    _id: orderId,
                    user: req.user._id
                });

                if (!order) {
                    results.push({
                        orderId,
                        status: 'not_found',
                        error: 'Order not found'
                    });
                    continue;
                }

                if (action === 'keep_server') {
                    // Do nothing, keep server version
                    results.push({
                        orderId,
                        status: 'kept_server_version'
                    });
                } else if (action === 'use_client') {
                    // Update with client data
                    const updatedOrder = await Order.findByIdAndUpdate(
                        orderId, {
                            ...data,
                            syncStatus: 'synced',
                            lastSynced: new Date(),
                            updatedAt: new Date()
                        }, { new: true }
                    );

                    results.push({
                        orderId,
                        status: 'updated_with_client_data',
                        serverId: updatedOrder._id
                    });
                } else if (action === 'merge') {
                    // Merge server and client data (custom logic based on your needs)
                    const mergedOrder = await Order.findByIdAndUpdate(
                        orderId, {
                            $set: {
                                ...data,
                                syncStatus: 'synced',
                                lastSynced: new Date(),
                                updatedAt: new Date()
                            }
                        }, { new: true }
                    );

                    results.push({
                        orderId,
                        status: 'merged',
                        serverId: mergedOrder._id
                    });
                }
            } catch (error) {
                results.push({
                    orderId: resolution.orderId,
                    status: 'error',
                    error: error.message
                });
            }
        }

        res.json({
            status: 'success',
            message: 'Conflicts resolved',
            data: results
        });
    } catch (error) {
        console.error('Resolve sync conflicts error:', error);
        res.status(500).json({
            status: 'error',
            message: 'Server error'
        });
    }
};

// Export all controller functions
module.exports = {
    createOrder,
    getOrders,
    getOrderById,
    updateOrder,
    deleteOrder,
    getOrderStats,
    generateInvoice,
    sendOrderEmail,
    getOrdersByDateRange,
    getOrdersByStatus,
    getDashboardSummary,
    syncBulkOrders,
    getPendingSyncOrders,
    markOrdersAsSynced,
    resolveSyncConflicts
};