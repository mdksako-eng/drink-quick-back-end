const express = require('express');
const router = express.Router();
const syncController = require('../controllers/sync.controller');
const { protect } = require('../middleware/auth.middleware');
const { validate } = require('../middleware/validation.middleware');
const validators = require('../utils/validators');

// All routes are protected
router.use(protect);

// Get sync status
router.get('/status', syncController.getSyncStatus);

// Get changes since last sync
router.get('/changes', syncController.getChangesSinceLastSync);

// Bulk sync data
router.post('/bulk', validate(validators.syncValidation), syncController.bulkSync);

// Resolve conflicts
router.post('/resolve', syncController.resolveConflicts);

// Clear sync data
router.delete('/clear', syncController.clearSyncData);

module.exports = router;