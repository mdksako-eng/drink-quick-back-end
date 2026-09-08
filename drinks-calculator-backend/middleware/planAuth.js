// backend/middleware/planAuth.js
// Feature gating based on the company's subscription plan.
//
// Usage (after the session middleware has set `req.user`):
//   router.get('/premium', requireSession(pool), requirePlan(['pro']), handler);

const PLAN_RANK = { free: 0, starter: 1, pro: 2 };

function planRank(plan) {
  return PLAN_RANK[String(plan || 'free').toLowerCase()] ?? 0;
}

// requirePlan(['starter','pro']) → the company's plan must be at least the
// lowest-ranked plan in the allowed list.
function requirePlan(allowedPlans = ['pro']) {
  const minRank = Math.min(...allowedPlans.map(planRank));
  return async (req, res, next) => {
    try {
      const user = req.user;
      if (!user) {
        return res
          .status(401)
          .json({ success: false, error: 'Authentication required' });
      }

      // Owners / administrators always have full access.
      if (['Administrator', 'Admin'].includes(user.role)) {
        return next();
      }

      const companyId = user.company_id;
      if (!companyId) {
        return res
          .status(403)
          .json({ success: false, error: 'UPGRADE_REQUIRED', plan: 'free' });
      }

      const result = await req.db.query(
        `SELECT plan, plan_expires_at FROM companies WHERE id = $1`,
        [companyId]
      );
      const company = result.rows[0];
      if (!company) {
        return res
          .status(403)
          .json({ success: false, error: 'UPGRADE_REQUIRED', plan: 'free' });
      }

      let plan = company.plan || 'free';
      // Auto-expire if the subscription period has lapsed.
      if (company.plan_expires_at && new Date(company.plan_expires_at) < new Date()) {
        plan = 'free';
      }

      if (planRank(plan) < minRank) {
        return res
          .status(403)
          .json({ success: false, error: 'UPGRADE_REQUIRED', plan });
      }

      req.companyPlan = plan;
      next();
    } catch (error) {
      next(error);
    }
  };
}

module.exports = { requirePlan, planRank, PLAN_RANK };
