// backend/utils/requestBody.js
// Webhook signatures are HMACs over the exact bytes that were sent. Express only
// hands those bytes over in the `verify` hook of the body parser (see server.js),
// so every webhook route reads them from here.

/**
 * The raw JSON body of a request.
 *
 * Falls back to a re-serialisation when the raw body was not captured — for a
 * body Express did not parse as JSON, or in a test that sends a plain object.
 * The fallback usually fails the signature check, which is the safe direction:
 * a genuine provider replayed from raw bytes is never accepted by accident.
 *
 * @param {object} req Express request
 * @returns {string} never null/undefined
 */
function rawBodyOf(req) {
  const raw = req ? req.rawBody : null;
  if (typeof raw === 'string' && raw.length > 0) return raw;
  if (Buffer.isBuffer(raw) && raw.length > 0) return raw.toString('utf8');
  return JSON.stringify((req && req.body) || {});
}

module.exports = { rawBodyOf };
