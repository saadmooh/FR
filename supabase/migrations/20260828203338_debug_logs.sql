-- WorkManager remote debug logging table
-- Stores diagnostic events from background isolate (WorkManager callback)
-- Independent of app state, SharedPreferences, or UI reopening

CREATE TABLE IF NOT EXISTS public.debug_logs (
  id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  event TEXT NOT NULL,
  details JSONB,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS debug_logs_event_idx ON public.debug_logs (event);
CREATE INDEX IF NOT EXISTS debug_logs_created_at_idx ON public.debug_logs (created_at DESC);

-- RLS: Service role can read/write for background tasks
ALTER TABLE public.debug_logs ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Service role can manage debug logs"
  ON public.debug_logs
  FOR ALL
  USING (auth.role() = 'service_role')
  WITH CHECK (auth.role() = 'service_role');

-- Optional: allow authenticated users to read their own logs (if we add user_id later)
-- CREATE POLICY "Users can read own debug logs"
--   ON public.debug_logs
--   FOR SELECT
--   USING (auth.uid() IS NOT NULL);