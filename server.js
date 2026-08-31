// Root-level shim so Render (which deploys from the repo root) can run the
// backend that lives in drinks-calculator-backend/.
//
// If you've set "Root Directory" to drinks-calculator-backend on the Render
// service, this file is unused and you can delete it.
require('./drinks-calculator-backend/server.js');