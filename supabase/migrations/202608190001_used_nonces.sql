-- Nonce replay-protection table for the ai-proxy edge function.
-- Each request's nonce is inserted here exactly once; a primary-key conflict
-- means the same request was already processed (replay) and must be rejected.

CREATE TABLE IF NOT EXISTS public.used_nonces (
  nonce TEXT PRIMARY KEY,
  user_id UUID NOT NULL,
  used_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS used_nonces_used_at_idx ON public.used_nonces (used_at);

-- Periodic cleanup of old nonces to keep the table small.
-- (The function relies only on the primary-key uniqueness; this is hygiene.)
ALTER TABLE public.used_nonces ENABLE ROW LEVEL SECURITY;

-- The edge function calls this with the authenticated user's JWT, so RLS is
-- evaluated as that user. Allow the user to claim (insert) their own nonce.
CREATE POLICY "Users can claim their own nonce"
  ON public.used_nonces
  FOR INSERT
  WITH CHECK (auth.uid() = user_id);

-- Allow the user to read their own nonces (useful for diagnostics).
CREATE POLICY "Users can read their own nonces"
  ON public.used_nonces
  FOR SELECT
  USING (auth.uid() = user_id);
