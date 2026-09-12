-- Consolidate all configurations into proxy_config table
-- Remove ai_proxy_config table and rate limiting configs
-- Add unopened posts limit

-- Add new configs to proxy_config table
INSERT INTO public.proxy_config (key, value, description) VALUES
  ('unopened_posts_limit', 50, 'Maximum number of unopened posts per user'),
  ('gemini_model', 0, 'Gemini model to use (stored as text in value_text)'),
  ('max_history_turns', 20, 'Maximum conversation history turns'),
  ('allow_debug_bypass', 0, 'Allow debug builds to bypass integrity check (0=false, 1=true)')
ON CONFLICT (key) DO NOTHING;

-- Add value_text column for string values (model name, etc.)
ALTER TABLE public.proxy_config ADD COLUMN IF NOT EXISTS value_text TEXT;

-- Update string configs
UPDATE public.proxy_config SET value_text = 'gemini-3.1-flash-lite' WHERE key = 'gemini_model';
UPDATE public.proxy_config SET value_text = 'true' WHERE key = 'allow_debug_bypass';

-- Drop ai_proxy_config table and function
DROP FUNCTION IF EXISTS public.get_ai_proxy_config();
DROP TABLE IF EXISTS public.ai_proxy_config;

-- Update get_proxy_config to include value_text for string configs
CREATE OR REPLACE FUNCTION public.get_proxy_config()
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_config JSONB := '{}'::jsonb;
BEGIN
  SELECT jsonb_object_agg(
    key,
    CASE
      WHEN value_text IS NOT NULL AND value_text != '' THEN to_jsonb(value_text)
      ELSE to_jsonb(value)
    END
  )
  INTO v_config
  FROM public.proxy_config;

  RETURN COALESCE(v_config, '{}'::jsonb);
END;
$$;

GRANT EXECUTE ON FUNCTION public.get_proxy_config TO service_role;