-- sql/legal_acceptances.sql
-- Consent evidence for the Terms of Service and the Privacy Policy.
--
-- WHY: the signup checkbox used to live only in the Flutter widget — nothing was
-- sent, stored or auditable, so nobody could prove a user ever agreed, and a
-- direct call to /api/auth/register skipped consent entirely.
--
-- The backend also creates this table at boot (idempotent), so running this script
-- by hand is only needed to put the schema in place before a deploy.
CREATE TABLE IF NOT EXISTS legal_acceptances (
  id BIGSERIAL PRIMARY KEY,
  user_id INTEGER NOT NULL,
  document TEXT NOT NULL,               -- 'terms' | 'privacy'
  version TEXT NOT NULL,                -- LEGAL_VERSION of the text served
  accepted_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
  ip TEXT                               -- first X-Forwarded-For hop, for evidence
);

CREATE INDEX IF NOT EXISTS legal_acceptances_user_idx
  ON legal_acceptances (user_id, document);

-- The anon key shipped inside the app must never read who accepted which legal
-- text, or from which IP. RLS with zero policies means no anon/authenticated
-- access at all; the backend connects as the table owner (postgres) and bypasses
-- RLS, so nothing in the app breaks. The backend also does this at boot.
ALTER TABLE legal_acceptances ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON legal_acceptances FROM anon, authenticated;

-- One pair of rows per registration. Audit a user with:
--   SELECT document, version, accepted_at, ip
--     FROM legal_acceptances WHERE user_id = 42 ORDER BY document;
