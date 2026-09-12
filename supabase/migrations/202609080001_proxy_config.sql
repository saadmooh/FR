-- Configuration table for proxy runtime settings (reschedule limits per importance)
-- Allows changing limits from Supabase Dashboard

CREATE TABLE IF NOT EXISTS public.proxy_config (
  key TEXT PRIMARY KEY,
  value INT NOT NULL,
  description TEXT,
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- Enable RLS
ALTER TABLE public.proxy_config ENABLE ROW LEVEL SECURITY;

-- Policy: anyone can read config (needed by edge function / app)
CREATE POLICY "Anyone can read proxy config"
  ON public.proxy_config
  FOR SELECT
  USING (true);

-- Policy: only service role can modify
CREATE POLICY "Service role can manage proxy config"
  ON public.proxy_config
  FOR ALL
  USING (auth.role() = 'service_role')
  WITH CHECK (auth.role() = 'service_role');

-- Insert default configuration (Day: 5, Week: 10, Month: 20)
INSERT INTO public.proxy_config (key, value, description) VALUES
  ('monthly_reschedule_limit_day', 5, 'Maximum reschedules per month for Day importance'),
  ('monthly_reschedule_limit_week', 10, 'Maximum reschedules per month for Week importance'),
  ('monthly_reschedule_limit_month', 20, 'Maximum reschedules per month for Month importance')
ON CONFLICT (key) DO NOTHING;

-- Function to get config value (with defaults)
CREATE OR REPLACE FUNCTION public.get_proxy_config()
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_config JSONB := '{}'::jsonb;
BEGIN
  SELECT jsonb_object_agg(key, to_jsonb(value))
  INTO v_config
  FROM public.proxy_config;

  RETURN COALESCE(v_config, '{}'::jsonb);
END;
$$;

GRANT EXECUTE ON FUNCTION public.get_proxy_config TO service_role;