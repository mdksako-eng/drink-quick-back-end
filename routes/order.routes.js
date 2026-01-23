const express = require('express');
const router = express.Router();
const orderController = require('../controllers/order.controller');
const { protect, authorize } = require('../middleware/auth.middleware');
const { validate } = require('../middleware/validation.middleware');
const validators = require('../utils/validators');

// All routes are protected
router.use(protect);

// ====================
// ORDER ROUTES
// ====================

// @desc    Get all orders
// @route   GET /api/orders
// @access  Private
router.get('/', orderController.getOrders);

// @desc    Get order statistics
// @route   GET /api/orders/stats
// @access  Private
router.get('/stats', orderController.getOrderStats);

// @desc    Get single order
// @route   GET /api/orders/:id
// @access  Private
router.get('/:id', orderController.getOrderById);

// @desc    Create new order
// @route   POST /api/orders
// @access  Private
router.post(
    '/',
    validate(validators.orderValidation),
    orderController.createOrder
);

// @desc    Update order
// @route   PUT /api/orders/:id
// @access  Private
router.put('/:id', orderController.updateOrder);

// @desc    Delete order (admin only)
// @route   DELETE /api/orders/:id
// @access  Private/Admin
router.delete(
    '/:id',
    authorize('Administrator'),
    orderController.deleteOrder
);

// @desc    Generate invoice PDF
// @route   POST /api/orders/:id/invoice
// @access  Private
router.post('/:id/invoice', orderController.generateInvoice);

// @desc    Send order confirmation email
// @route   POST /api/orders/:id/send-email
// @access  Private
router.post('/:id/send-email', orderController.sendOrderEmail);

// @desc    Get orders by date range
// @route   GET /api/orders/filter/date
// @access  Private
router.get('/filter/date', orderController.getOrdersByDateRange);

// @desc    Get orders by status
// @route   GET /api/orders/filter/status/:status
// @access  Private
router.get('/filter/status/:status', orderController.getOrdersByStatus);

// @desc    Get orders summary for dashboard
// @route   GET /api/orders/dashboard/summary
// @access  Private
router.get('/dashboard/summary', orderController.getDashboardSummary);

// @desc    Export orders to CSV/Excel
// @route   GET /api/orders/export/:format
// @access  Private
router.get('/export/:format', orderController.exportOrders);

// ====================
// OFFLINE SYNC ROUTES
// ====================

// @desc    Bulk sync orders from offline
// @route   POST /api/orders/sync/bulk
// @access  Private
router.post('/sync/bulk', orderController.syncBulkOrders);

// @desc    Get pending sync orders
// @route   GET /api/orders/sync/pending
// @access  Private
router.get('/sync/pending', orderController.getPendingSyncOrders);

// @desc    Mark orders as synced
// @route   POST /api/orders/sync/mark-synced
// @access  Private
router.post('/sync/mark-synced', orderController.markOrdersAsSynced);

// @desc    Resolve sync conflicts
// @route   POST /api/orders/sync/resolve-conflicts
// @access  Private
router.post('/sync/resolve-conflicts', orderController.resolveSyncConflicts);

module.exports = router;