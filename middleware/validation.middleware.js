const { validationResult } = require('express-validator');

const validate = (validations) => {
    return async(req, res, next) => {
        await Promise.all(validations.map(validation => validation.run(req)));

        const errors = validationResult(req);
        if (errors.isEmpty()) {
            return next();
        }

        const errorMessages = errors.array().map(err => ({
            field: err.param,
            message: err.msg
        }));

        res.status(400).json({
            status: 'error',
            message: 'Validation failed',
            errors: errorMessages
        });
    };
};

// Custom validator for file uploads
const validateFile = (fieldName, options = {}) => {
    return (req, res, next) => {
        if (!req.file && options.required) {
            return res.status(400).json({
                status: 'error',
                message: `${fieldName} is required`
            });
        }

        if (req.file) {
            // Check file size
            if (options.maxSize && req.file.size > options.maxSize) {
                return res.status(400).json({
                    status: 'error',
                    message: `File size should not exceed ${options.maxSize / 1024 / 1024}MB`
                });
            }

            // Check file type
            if (options.allowedTypes && !options.allowedTypes.includes(req.file.mimetype)) {
                return res.status(400).json({
                    status: 'error',
                    message: `File type not allowed. Allowed types: ${options.allowedTypes.join(', ')}`
                });
            }
        }

        next();
    };
};

// Validate MongoDB ID
const validateId = (paramName) => {
    return (req, res, next) => {
        const id = req.params[paramName];

        if (!id || !id.match(/^[0-9a-fA-F]{24}$/)) {
            return res.status(400).json({
                status: 'error',
                message: `Invalid ${paramName} ID`
            });
        }

        next();
    };
};

module.exports = {
    validate,
    validateFile,
    validateId
};