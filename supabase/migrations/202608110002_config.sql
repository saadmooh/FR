-- Configuration table for ai-proxy runtime settings
-- Allows changing rate limits and other settings from Supabase Dashboard

CREATE TABLE IF NOT EXISTS public.ai_proxy_config (
  key TEXT PRIMARY KEY,
  value JSONB NOT NULL,
  description TEXT,
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- Enable RLS
ALTER TABLE public.ai_proxy_config ENABLE ROW LEVEL SECURITY;

-- Policy: anyone can read config (needed by edge function)
CREATE POLICY "Anyone can read ai proxy config"
  ON public.ai_proxy_config
  FOR SELECT
  USING (true);

-- Policy: only service role can modify
CREATE POLICY "Service role can manage ai proxy config"
  ON public.ai_proxy_config
  FOR ALL
  USING (auth.role() = 'service_role')
  WITH CHECK (auth.role() = 'service_role');

-- Insert default configuration
INSERT INTO public.ai_proxy_config (key, value, description) VALUES
  ('rate_limit_per_minute', '10', 'Maximum requests per minute per user'),
  ('rate_limit_per_hour', '1', 'Maximum requests per hour per user'),
  ('rate_limit_per_month', '500', 'Maximum requests per month per user'),
  ('gemini_model', '"gemini-3.1-flash-lite"', 'Gemini model to use'),
  ('max_history_turns', '20', 'Maximum conversation history turns'),
  ('allow_debug_bypass', 'false', 'Allow debug builds to bypass integrity check')
ON CONFLICT (key) DO NOTHING;

-- Function to get config value (with defaults)
CREATE OR REPLACE FUNCTION public.get_ai_proxy_config()
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_config JSONB := '{}'::jsonb;
BEGIN
  SELECT jsonb_object_agg(key, value)
  INTO v_config
  FROM public.ai_proxy_config;

  RETURN COALESCE(v_config, '{}'::jsonb);
END;
$$;

GRANT EXECUTE ON FUNCTION public.get_ai_proxy_config TO service_role;