-- Entitlements (RevenueCat -> webhook) + used_nonces hygiene.
--
-- IMPORTANT DESIGN NOTE:
-- The app calls Purchases.logIn(firebaseUid), so RevenueCat's app_user_id is
-- the FIREBASE UID, which is NOT a UUID and does NOT exist in auth.users.
-- Therefore entitlements.user_id is TEXT (Firebase UID) with NO foreign key
-- to auth.users. The session-token edge function authenticates the caller via
-- a Firebase ID token and reads entitlements by the token's `sub` claim
-- (the same Firebase UID), keeping the key space consistent end-to-end.

CREATE TABLE IF NOT EXISTS public.entitlements (
  user_id        TEXT PRIMARY KEY,
  product_id     TEXT,
  entitlement_id TEXT,
  status         TEXT NOT NULL CHECK (status IN ('active','expired','billing_issue','cancelled')),
  expires_at     TIMESTAMPTZ,
  store          TEXT,
  updated_at     TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

ALTER TABLE public.entitlements ENABLE ROW LEVEL SECURITY;

-- Read-your-own-row policy. auth.uid()::text never equals a Firebase UID in
-- the current setup (Supabase issues its own UUIDs for third-party auth), so
-- this is intentionally inert today; it becomes meaningful if the identifiers
-- are ever unified. All writes go through service_role in edge functions,
-- which bypasses RLS entirely. No INSERT/UPDATE/DELETE policies on purpose.
CREATE POLICY "Users can read own entitlement"
  ON public.entitlements
  FOR SELECT
  USING (auth.uid()::text = user_id);

CREATE INDEX IF NOT EXISTS idx_entitlements_user_status
  ON public.entitlements (user_id, status);

-- ---------------------------------------------------------------------------
-- used_nonces: created by migration 202608190001_used_nonces.sql
-- (nonce TEXT PRIMARY KEY, user_id UUID NOT NULL, used_at TIMESTAMPTZ).
-- RLS + owner policies already exist there. Only hygiene is added below;
-- the IF NOT EXISTS keeps this migration safe on a fresh database too.
-- ---------------------------------------------------------------------------

CREATE TABLE IF NOT EXISTS public.used_nonces (
  nonce   TEXT PRIMARY KEY,
  user_id UUID NOT NULL,
  used_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS used_nonces_used_at_idx ON public.used_nonces (used_at);

-- ai-proxy claims nonces with the caller's Supabase UUID, while session-token
-- authenticates via Firebase ID tokens whose `sub` (Firebase UID) is not a
-- UUID. Make the column nullable so both flows can share replay protection.
ALTER TABLE public.used_nonces ALTER COLUMN user_id DROP NOT NULL;

ALTER TABLE public.used_nonces ENABLE ROW LEVEL SECURITY;

-- SECURITY DEFINER cleanup function so pg_cron (which runs as postgres with
-- RLS bypass only via role permissions) can delete regardless of policies.
CREATE OR REPLACE FUNCTION public.cleanup_used_nonces()
RETURNS void
LANGUAGE sql
SECURITY DEFINER
SET search_path = public
AS $$
  DELETE FROM public.used_nonces WHERE used_at < NOW() - INTERVAL '24 hours';
$$;

REVOKE ALL ON FUNCTION public.cleanup_used_nonces() FROM public, anon, authenticated;

-- Schedule hourly cleanup if pg_cron is available (hosted Supabase has it).
-- Named dollar-quotes ($mig$ / $sql$): a bare $$ inside the block would
-- terminate the DO body early.
DO $mig$
BEGIN
  IF EXISTS (SELECT 1 FROM pg_available_extensions WHERE name = 'pg_cron') THEN
    EXECUTE 'CREATE EXTENSION IF NOT EXISTS pg_cron WITH SCHEMA extensions';

    -- Idempotent reschedule.
    PERFORM cron.unschedule('cleanup_used_nonces')
    WHERE EXISTS (SELECT 1 FROM cron.job WHERE jobname = 'cleanup_used_nonces');

    PERFORM cron.schedule(
      'cleanup_used_nonces',
      '17 * * * *',
      $sql$SELECT public.cleanup_used_nonces()$sql$
    );
  ELSE
    RAISE NOTICE 'pg_cron not available; schedule public.cleanup_used_nonces() manually.';
  END IF;
END
$mig$;
