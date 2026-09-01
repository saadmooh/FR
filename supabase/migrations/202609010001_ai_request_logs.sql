-- Simple AI request log table
-- Each row records one AI proxy request with just a title and content.
-- Limits/enforcement stays in Supabase; this is only a lightweight audit log.

CREATE TABLE IF NOT EXISTS public.ai_request_logs (
  id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  user_id UUID,
  title TEXT NOT NULL,
  content TEXT NOT NULL,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS ai_request_logs_created_at_idx
  ON public.ai_request_logs (created_at DESC);
CREATE INDEX IF NOT EXISTS ai_request_logs_user_id_idx
  ON public.ai_request_logs (user_id);

-- RLS: service role can write; the edge function inserts via service_role.
ALTER TABLE public.ai_request_logs ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Service role can manage ai request logs"
  ON public.ai_request_logs
  FOR ALL
  USING (auth.role() = 'service_role')
  WITH CHECK (auth.role() = 'service_role');
