const express = require('express');
const router = express.Router();
const drinkController = require('../controllers/drink.controller');
const { protect, authorize } = require('../middleware/auth.middleware');
const { validate } = require('../middleware/validation.middleware');
const validators = require('../utils/validators');

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

// Create drink (staff and above)
router.post(
    '/',
    authorize('Administrator', 'Manager', 'Staff'),
    validate(validators.drinkValidation),
    drinkController.createDrink
);

// Update drink
router.put(
    '/:id',
    validate(validators.drinkValidation),
    drinkController.updateDrink
);

// Delete drink
router.delete('/:id', drinkController.deleteDrink);

// Bulk sync drinks
router.post('/sync', validate(validators.syncValidation), drinkController.syncDrinks);

module.exports = router;