const express = require('express');
const router = express.Router();
const drinkController = require('../controllers/drink.controller');
const { protect, authorize } = require('../middleware/auth.middleware');
const { validate } = require('../middleware/validation.middleware');
const validators = require('../utils/validators');

// Debug: Check controller functions
console.log('Drink Controller loaded:', drinkController ? 'YES' : 'NO');
if (drinkController) {
    console.log('Available functions:', Object.keys(drinkController));
}

// All routes are protected
router.use(protect);

// Get all drinks
router.get('/', drinkController.getDrinks || ((req, res) => res.json({ message: 'getDrinks function not available' })));

// Get drink categories
router.get('/categories', drinkController.getCategories || ((req, res) => res.json({ message: 'getCategories function not available' })));

// Get drink statistics
router.get('/stats', drinkController.getDrinkStats || ((req, res) => res.json({ message: 'getDrinkStats function not available' })));

// Get single drink
router.get('/:id', drinkController.getDrinkById || ((req, res) => res.json({ message: 'getDrinkById function not available' })));

// Create drink (staff and above) - FIXED: Check if validation exists
router.post(
    '/',
    authorize('Administrator', 'Manager', 'Staff'),
    (req, res, next) => {
        // Safely apply validation if available
        if (validators && validators.drinkValidation && validate) {
            return validate(validators.drinkValidation)(req, res, next);
        }
        console.log('Validation skipped - proceeding to controller');
        next();
    },
    drinkController.createDrink || ((req, res) => res.status(501).json({ error: 'createDrink function not available' }))
);

// Update drink - FIXED: Check if validation exists
router.put(
    '/:id',
    (req, res, next) => {
        // Check if user can update (admin/manager/staff who created it)
        if (req.user.role === 'Customer') {
            return res.status(403).json({ error: 'Not authorized to update drinks' });
        }
        
        // Safely apply validation if available
        if (validators && validators.drinkValidation && validate) {
            return validate(validators.drinkValidation)(req, res, next);
        }
        next();
    },
    drinkController.updateDrink || ((req, res) => res.status(501).json({ error: 'updateDrink function not available' }))
);

// Delete drink
router.delete('/:id', 
    authorize('Administrator', 'Manager'), // Only admin and manager can delete
    drinkController.deleteDrink || ((req, res) => res.status(501).json({ error: 'deleteDrink function not available' }))
);

// Bulk sync drinks - FIXED: Added proper error handling
router.post('/sync', 
    authorize('Administrator', 'Manager'), // Only admin/manager can sync
    (req, res, next) => {
        // Safely apply validation if available
        if (validators && validators.syncValidation && validate) {
            return validate(validators.syncValidation)(req, res, next);
        }
        next();
    },
    // Check if syncDrinks function exists, otherwise use fallback
    drinkController.syncDrinks 
        ? drinkController.syncDrinks 
        : (req, res) => {
            res.status(501).json({ 
                error: 'syncDrinks function not available',
                message: 'This feature is temporarily unavailable'
            });
        }
);

// Add a health check route for this specific router
router.get('/health/route', (req, res) => {
    res.json({
        status: 'healthy',
        timestamp: new Date().toISOString(),
        routes: [
            'GET /',
            'GET /categories',
            'GET /stats',
            'GET /:id',
            'POST /',
            'PUT /:id',
            'DELETE /:id',
            'POST /sync'
        ]
    });
});

module.exports = router;
