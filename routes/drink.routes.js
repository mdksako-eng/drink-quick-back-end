const express = require('express');
const router = express.Router();
const drinkController = require('../controllers/drink.controller');
const { protect, authorize } = require('../middleware/auth.middleware');
const { validate } = require('../middleware/validation.middleware');
const validators = require('../utils/validators');

// Debug: Check if validators exist
console.log('Validators loaded:', validators ? Object.keys(validators) : 'NOT FOUND');

// All routes are protected
router.use(protect);

// Get all drinks
router.get('/', drinkController.getDrinks);

// Get drink categories
router.get('/categories', drinkController.getCategories);

// Get drink statistics
router.get('/stats', drinkController.getDrinkStats);

// Get single drink
router.get('/:id', drinkController.getDrinkById);

// Create drink (staff and above) - FIXED LINE 42
router.post(
    '/',
    authorize('Administrator', 'Manager', 'Staff'),
    (req, res, next) => {
        // Check if validation schema exists
        if (!validators || !validators.drinkValidation) {
            console.warn('drinkValidation schema not found, skipping validation');
            return next();
        }
        validate(validators.drinkValidation)(req, res, next);
    },
    drinkController.createDrink
);

// Update drink
router.put(
    '/:id',
    (req, res, next) => {
        if (!validators || !validators.drinkValidation) {
            console.warn('Validation schema not found');
            return next();
        }
        validate(validators.drinkValidation)(req, res, next);
    },
    drinkController.updateDrink
);

// Delete drink
router.delete('/:id', drinkController.deleteDrink);

// Bulk sync drinks - FIXED LINE 55
router.post('/sync', 
    (req, res, next) => {
        if (!validators || !validators.syncValidation) {
            console.warn('syncValidation schema not found');
            return next();
        }
        validate(validators.syncValidation)(req, res, next);
    },
    drinkController.syncDrinks
);

module.exports = router;
