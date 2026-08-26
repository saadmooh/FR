// ai-proxy — Secure proxy that forwards prompts to the Gemini API.
//
// Security layers (in order):
//   1. Supabase Auth: rejects requests without a valid user session.
//   2. Body parsing: prompt/history/timestamp are read early because the
//      integrity + nonce-binding checks below need them.
//   3. Play Integrity: verifies the client's integrity token against
//      Google's Play Integrity API, confirms the nonce matches, AND now
//      pins the signing certificate so only your real signed APK passes.
//      (Implementation shared with session-token via ../_shared/integrity.ts)
//   4. Request binding: the nonce must be derived from THIS request's
//      content (prompt + user + timestamp), not just present — this stops
//      a token/nonce pair captured from one request being replayed with a
//      different prompt.
//   5. Nonce replay protection: each nonce can be claimed (used) exactly
//      once, stored in the `used_nonces` table, closing the "token farm"
//      window where a valid pair is reused multiple times within its
//      5-minute validity.
//   6. Subscription: a short-lived session JWT issued by the session-token
//      function must be present and valid (signature + exp + entitlement).
//      Issued only after RevenueCat reported an active Pro entitlement.
//   7. Rate limiting: per-user minute/hour/month windows.
//
// Server-side secrets (set with `supabase secrets set`, NEVER in code):
//   GEMINI_API_KEY              — Google AI (Gemini) API key
//   GOOGLE_SERVICE_ACCOUNT_JSON — full contents of your GCP service-account
//                                  JSON (used to call Play Integrity)
//   EXPECTED_PACKAGE_NAME       — optional, default com.saadmohammed2000.flex_reminder
//   EXPECTED_CERT_SHA256        — comma-separated SHA-256 cert digest(s) of
//                                  your Play signing key(s), from Play Console
//                                  → Setup → App integrity. REQUIRED for
//                                  certificate pinning to take effect.
//   SESSION_TOKEN_SECRET        — HMAC secret for session JWTs; MUST be the
//                                  same value the session-token function uses.

import { createClient } from 'jsr:@supabase/supabase-js@2';

import { verifyIntegrityToken, sha256Base64 } from '../_shared/integrity.ts';
import { verifySessionToken } from '../_shared/session_jwt.ts';

const SUPABASE_URL = Deno.env.get('SUPABASE_URL') ?? '';
const SUPABASE_ANON_KEY =
  Deno.env.get('SUPABASE_ANON_KEY') ?? Deno.env.get('SUPABASE_PUBLISHABLE_KEY') ?? '';

const GEMINI_API_KEY = Deno.env.get('GEMINI_API_KEY') ?? '';
const SESSION_TOKEN_SECRET = Deno.env.get('SESSION_TOKEN_SECRET') ?? '';
const EXPECTED_PACKAGE_NAME =
  Deno.env.get('EXPECTED_PACKAGE_NAME') ?? 'com.saadmohammed2000.flex_reminder';

// Certificate pinning: one or more SHA-256 digests (as returned by Play
// Integrity's certificateSha256Digest field), comma-separated. Supports
// multiple values so you can rotate signing keys without downtime.
const EXPECTED_CERT_HASHES = (Deno.env.get('EXPECTED_CERT_SHA256') ?? '')
  .split(',')
  .map((s) => s.trim())
  .filter(Boolean);

// Config cache (TTL: 60 seconds)
let configCache: {
  rateLimitPerMinute: number;
  rateLimitPerHour: number;
  rateLimitPerMonth: number;
  geminiModel: string;
  maxHistoryTurns: number;
  allowDebugBypass: boolean;
} | null = null;
let configCacheExpiry = 0;

async function loadConfig(supabase: ReturnType<typeof createClient>): Promise<void> {
  const now = Date.now();
  if (configCache && now < configCacheExpiry) {
    return;
  }

  const { data, error } = await supabase.rpc('get_ai_proxy_config');
  if (error) {
    console.error('Failed to load config, using defaults:', error);
    configCache = {
      rateLimitPerMinute: 10,
      rateLimitPerHour: 1,
      rateLimitPerMonth: 500,
      geminiModel: 'gemini-3.1-flash-lite',
      maxHistoryTurns: 20,
      allowDebugBypass: false,
    };
  } else {
    const cfg = data ?? {};
    configCache = {
      rateLimitPerMinute: Number(cfg.rate_limit_per_minute ?? 10),
      rateLimitPerHour: Number(cfg.rate_limit_per_hour ?? 1),
      rateLimitPerMonth: Number(cfg.rate_limit_per_month ?? 500),
      geminiModel: cfg.gemini_model ?? 'gemini-3.1-flash-lite',
      maxHistoryTurns: Number(cfg.max_history_turns ?? 20),
      allowDebugBypass: cfg.allow_debug_bypass === true || cfg.allow_debug_bypass === 'true',
    };
  }
  configCacheExpiry = now + 60 * 1000;
}

// ---------------------------------------------------------------------------
// Rate limiting (database-backed, works across function instances)
// ---------------------------------------------------------------------------

async function checkRateLimit(
  supabase: ReturnType<typeof createClient>,
  userId: string,
): Promise<{ allowed: boolean; period?: 'minute' | 'hour' | 'month' }> {
  await loadConfig(supabase);
  const cfg = configCache!;

  const minuteAgo = new Date(Date.now() - 60 * 1000).toISOString();
  const hourAgo = new Date(Date.now() - 60 * 60 * 1000).toISOString();
  const monthStart = new Date();
  monthStart.setDate(1);
  monthStart.setHours(0, 0, 0, 0);
  const monthStartIso = monthStart.toISOString();

  const { data, error } = await supabase.rpc('check_rate_limit', {
    p_user_id: userId,
    p_minute_limit: cfg.rateLimitPerMinute,
    p_hour_limit: cfg.rateLimitPerHour,
    p_month_limit: cfg.rateLimitPerMonth,
    p_minute_window_start: minuteAgo,
    p_hour_window_start: hourAgo,
    p_month_window_start: monthStartIso,
  });

  if (error) {
    console.error('Rate limit RPC error:', error);
    return { allowed: true };
  }

  if (!data?.allowed) {
    return { allowed: false, period: data?.period };
  }

  return { allowed: true };
}

// ---------------------------------------------------------------------------
// Nonce replay protection
// ---------------------------------------------------------------------------

/**
 * Atomically claims a nonce for a user. Returns false if the nonce has
 * already been used (primary-key conflict on `used_nonces.nonce`), which
 * means this exact request was already processed — reject it as a replay.
 */
async function claimNonce(
  supabase: ReturnType<typeof createClient>,
  nonce: string,
  userId: string,
): Promise<boolean> {
  const { error } = await supabase
    .from('used_nonces')
    .insert({ nonce, user_id: userId });
  if (error) {
    // Only a true unique violation (Postgres 23505) means this exact nonce was
    // already claimed → a genuine replay. Any other error (table missing, RLS,
    // transient) must NOT be reported as a replay, otherwise healthy requests
    // are wrongly rejected. Fail open for non-replay DB errors.
    const isUniqueViolation = (error as { code?: string }).code === '23505';
    if (isUniqueViolation) {
      return false;
    }
    logError('claimNonce_db_error', error, { code: (error as { code?: string }).code });
    return true;
  }
  return true;
}

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

function jsonError(
  status: number,
  code: string,
  message: string,
  diagnostic?: Record<string, unknown>,
): Response {
  const body: Record<string, unknown> = { error: { code, message } };
  if (diagnostic) {
    body.diagnostic = diagnostic;
  }
  return new Response(JSON.stringify(body), {
    status,
    headers: { 'Content-Type': 'application/json' },
  });
}

function logRequest(stage: string, data: Record<string, unknown>): void {
  const logEntry = {
    timestamp: new Date().toISOString(),
    stage,
    function: 'ai-proxy',
    ...data,
  };
  console.log(JSON.stringify(logEntry));
}

function logError(stage: string, error: unknown, context?: Record<string, unknown>): void {
  const errorMessage = error instanceof Error ? error.message : String(error);
  const errorStack = error instanceof Error ? error.stack : undefined;
  const logEntry = {
    timestamp: new Date().toISOString(),
    stage,
    function: 'ai-proxy',
    level: 'ERROR',
    error: errorMessage,
    stack: errorStack,
    ...context,
  };
  console.error(JSON.stringify(logEntry));
}

function cors(): Headers {
  return new Headers({
    'Access-Control-Allow-Origin': '*',
    'Access-Control-Allow-Methods': 'POST, OPTIONS',
    'Access-Control-Allow-Headers':
      'authorization, x-client-info, apikey, content-type, x-integrity-token, x-request-nonce, x-session-token',
  });
}


// ---------------------------------------------------------------------------
// Gemini call
// ---------------------------------------------------------------------------

interface ChatTurn {
  role: string;
  content: string;
}

async function callGemini(prompt: string, history: ChatTurn[], model: string): Promise<string> {
  const contents = history.map((turn) => ({
    role: turn.role === 'assistant' ? 'model' : 'user',
    parts: [{ text: turn.content }],
  }));
  contents.push({ role: 'user', parts: [{ text: prompt }] });

  const res = await fetch(
    `https://generativelanguage.googleapis.com/v1beta/models/${model}:generateContent?key=${GEMINI_API_KEY}`,
    {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({
        contents,
        generationConfig: {
          temperature: 0.7,
          maxOutputTokens: 2048,
        },
      }),
    },
  );

  if (!res.ok) {
    const body = await res.text();
    throw new Error(`Gemini error ${res.status}: ${body.slice(0, 500)}`);
  }

  const data = await res.json();
  const text =
    data?.candidates?.[0]?.content?.parts?.map((p: { text?: string }) => p.text ?? '').join('') ?? '';
  if (!text) {
    throw new Error('Gemini returned an empty response');
  }
  return text;
}

// ---------------------------------------------------------------------------
// Main handler
// ---------------------------------------------------------------------------

Deno.serve(async (req: Request) => {
  const requestId = crypto.randomUUID();
  const startTime = Date.now();
  const headers = cors();

  logRequest('request_start', {
    requestId,
    method: req.method,
    url: req.url,
    userAgent: req.headers.get('User-Agent'),
    hasAuthHeader: !!req.headers.get('Authorization'),
    hasIntegrityToken: !!req.headers.get('X-Integrity-Token'),
    hasRequestNonce: !!req.headers.get('X-Request-Nonce'),
    isDebugBuild: req.headers.get('X-Debug-Build') === 'true',
  });

  if (req.method === 'OPTIONS') {
    logRequest('request_end', { requestId, status: 204, durationMs: Date.now() - startTime });
    return new Response(null, { status: 204, headers });
  }
  if (req.method !== 'POST') {
    logRequest('request_end', {
      requestId,
      status: 405,
      durationMs: Date.now() - startTime,
      error: 'METHOD_NOT_ALLOWED',
    });
    return jsonError(405, 'METHOD_NOT_ALLOWED', 'Only POST is allowed');
  }

  // ---- 1. Supabase Auth -----------------------------------------------------
  const authHeader = req.headers.get('Authorization') ?? '';
  const supabase = createClient(SUPABASE_URL, SUPABASE_ANON_KEY, {
    global: { headers: { Authorization: authHeader } },
  });

  logRequest('auth_start', { requestId });
  const {
    data: { user },
    error: authError,
  } = await supabase.auth.getUser();

  if (authError || !user) {
    logError('auth_failed', authError ?? new Error('No user'), { requestId });
    logRequest('request_end', {
      requestId,
      status: 401,
      durationMs: Date.now() - startTime,
      error: 'UNAUTHENTICATED',
    });
    return jsonError(401, 'UNAUTHENTICATED', 'You must be signed in first');
  }
  logRequest('auth_success', { requestId, userId: user.id });

  await loadConfig(supabase);
  const cfg = configCache!;

  // ---- 2. Parse body ---------------------------------------------------------
  // Moved ahead of Play Integrity: the nonce-binding check (step 4) needs
  // `prompt` and `timestamp` from the body, so we must parse it first.
  logRequest('body_parse_start', { requestId, userId: user.id });
  let body: { prompt?: unknown; conversationHistory?: unknown; timestamp?: unknown };
  try {
    body = await req.json();
  } catch (e) {
    logError('body_parse_failed', e, { requestId, userId: user.id });
    logRequest('request_end', {
      requestId,
      status: 400,
      durationMs: Date.now() - startTime,
      error: 'INVALID_BODY',
    });
    return jsonError(400, 'INVALID_BODY', 'Request body must be valid JSON');
  }

  const prompt = typeof body.prompt === 'string' ? body.prompt.trim() : '';
  if (!prompt) {
    logRequest('request_end', {
      requestId,
      status: 400,
      durationMs: Date.now() - startTime,
      error: 'EMPTY_PROMPT',
    });
    return jsonError(400, 'EMPTY_PROMPT', 'Prompt cannot be empty');
  }
  if (prompt.length > 4000) {
    logRequest('request_end', {
      requestId,
      status: 400,
      durationMs: Date.now() - startTime,
      error: 'PROMPT_TOO_LONG',
    });
    return jsonError(400, 'PROMPT_TOO_LONG', 'Prompt is too long (max 4000 chars)');
  }

  const clientTimestamp = typeof body.timestamp === 'number' ? body.timestamp : null;
  if (!clientTimestamp) {
    logRequest('request_end', {
      requestId,
      status: 400,
      durationMs: Date.now() - startTime,
      error: 'MISSING_TIMESTAMP',
    });
    return jsonError(
      400,
      'MISSING_TIMESTAMP',
      'timestamp is required to bind the request to its integrity nonce',
    );
  }

  const history: ChatTurn[] = Array.isArray(body.conversationHistory)
    ? (body.conversationHistory as ChatTurn[])
        .filter(
          (t) => t && typeof t.content === 'string' && (t.role === 'user' || t.role === 'assistant'),
        )
        .slice(-cfg.maxHistoryTurns)
    : [];
  logRequest('body_parse_ok', {
    requestId,
    userId: user.id,
    promptLength: prompt.length,
    historyTurns: history.length,
  });

  // ---- 3. Play Integrity ------------------------------------------------------
  const integrityToken = req.headers.get('X-Integrity-Token');
  const requestNonce = req.headers.get('X-Request-Nonce');
  const isDebugBuild = req.headers.get('X-Debug-Build') === 'true';

  // Expected nonce is derived from THIS request's content. Computed up-front so
  // both the token-nonce check and the request-binding check use the same value.
  const expectedNonceInput = `${prompt}|${user.id}|${clientTimestamp}`;
  const expectedNonceHash = await sha256Base64(expectedNonceInput);

  logRequest('integrity_start', {
    requestId,
    userId: user.id,
    isDebugBuild,
    hasToken: !!integrityToken,
    hasNonce: !!requestNonce,
  });

  if (cfg.allowDebugBypass && isDebugBuild) {
    logRequest('integrity_bypass', { requestId, userId: user.id, reason: 'debug_build' });
  } else {
    if (!integrityToken || !requestNonce) {
      logError('integrity_missing', new Error('Missing integrity token or nonce'), {
        requestId,
        userId: user.id,
      });
      logRequest('request_end', {
        requestId,
        status: 403,
        durationMs: Date.now() - startTime,
        error: 'INTEGRITY_MISSING',
      });
      return jsonError(403, 'INTEGRITY_MISSING', 'Integrity token and nonce are required', {
        stage: 'request_validation',
        decodeSuccess: false,
        errorMessage: 'Missing integrity token or nonce',
      });
    }

    const { passed, diagnostic } = await verifyIntegrityToken(
      integrityToken,
      requestNonce,
      expectedNonceHash,
    );
    logRequest('integrity_result', {
      requestId,
      userId: user.id,
      passed,
      stage: diagnostic.stage,
      failedChecks: diagnostic.failedChecks,
    });

    if (!passed) {
      logError('integrity_failed', new Error('Integrity check failed'), {
        requestId,
        userId: user.id,
        diagnostic,
      });
      logRequest('request_end', {
        requestId,
        status: 403,
        durationMs: Date.now() - startTime,
        error: 'INTEGRITY_FAILED',
      });

      // Pick an actionable message so a legit-but-unregistered tester is not
      // confused with a real tampering attempt.
      const failed = diagnostic.failedChecks ?? [];
      let message = 'App integrity check failed, update the app to the latest version';
      if (failed.includes('licensingUnevaluated')) {
        message =
          'تعذّر التحقق من ترخيص Play. إذا كنت من المختبِرين، تأكد أن حساب Google الخاص بك مسجّل كمختبِر في Play Console وحمّلت التطبيق عبر رابط المتجر (وليس ملف APK مُثبّت جانبياً).';
      } else if (failed.includes('licensingNotVerified')) {
        message =
          'نسخة التطبيق غير مرخّصة من Google Play. يرجى تثبيت النسخة الرسمية من متجر Play.';
      }

      return jsonError(403, 'INTEGRITY_FAILED', message, diagnostic);
    }

    // ---- 4. Request binding: nonce must be derived from THIS request ------
    // Stops a captured (token, nonce) pair from being replayed with a
    // different prompt within its 5-minute validity window.
    if (expectedNonceHash !== requestNonce) {
      logError('nonce_binding_mismatch', new Error('nonce does not match request content'), {
        requestId,
        userId: user.id,
      });
      logRequest('request_end', {
        requestId,
        status: 403,
        durationMs: Date.now() - startTime,
        error: 'NONCE_BINDING_MISMATCH',
      });
      return jsonError(
        403,
        'NONCE_BINDING_MISMATCH',
        'Request content does not match the attached integrity token',
      );
    }

    // ---- 5. Nonce replay protection: claim it, one use only ---------------
    const nonceClaimed = await claimNonce(supabase, requestNonce, user.id);
    if (!nonceClaimed) {
      logError('nonce_replay', new Error('nonce already used'), { requestId, userId: user.id });
      logRequest('request_end', {
        requestId,
        status: 403,
        durationMs: Date.now() - startTime,
        error: 'NONCE_REPLAY',
      });
      return jsonError(403, 'NONCE_REPLAY', 'This request has already been processed');
    }
  }

  // ---- 6. Subscription: valid session token required -------------------------
  // Issued by the session-token function only when RevenueCat reported an
  // active Pro entitlement for the caller (Firebase UID). Debug builds that
  // bypass integrity also bypass this layer so local development keeps
  // working; allow_debug_bypass defaults to false in production config.
  if (!(cfg.allowDebugBypass && isDebugBuild)) {
    const sessionVerdict = await verifySessionToken(
      req.headers.get('X-Session-Token') ?? '',
      SESSION_TOKEN_SECRET,
    );
    logRequest('session_token_result', { requestId, userId: user.id, ...sessionVerdict });
    if (!sessionVerdict.valid) {
      logError('subscription_required', new Error('invalid or missing session token'), {
        requestId,
        userId: user.id,
        reason: sessionVerdict.reason,
      });
      logRequest('request_end', {
        requestId,
        status: 403,
        durationMs: Date.now() - startTime,
        error: 'SUBSCRIPTION_REQUIRED',
      });
      return jsonError(
        403,
        'SUBSCRIPTION_REQUIRED',
        'subscription required',
        sessionVerdict.reason ? { reason: sessionVerdict.reason } : undefined,
      );
    }
  }

  // ---- 7. Rate limiting -------------------------------------------------------
  logRequest('rate_limit_start', { requestId, userId: user.id });
  const limit = await checkRateLimit(supabase, user.id);
  if (!limit.allowed) {
    logError('rate_limit_exceeded', new Error(`Rate limit exceeded: ${limit.period}`), {
      requestId,
      userId: user.id,
      period: limit.period,
    });
    logRequest('request_end', {
      requestId,
      status: 429,
      durationMs: Date.now() - startTime,
      error: `RATE_LIMIT_${limit.period?.toUpperCase()}`,
    });
    const isMinute = limit.period === 'minute';
    const isHour = limit.period === 'hour';
    return jsonError(
      429,
      isMinute ? 'RATE_LIMIT_MINUTE' : isHour ? 'RATE_LIMIT_HOUR' : 'RATE_LIMIT_MONTH',
      isMinute
        ? 'Rate limit exceeded, try again in a minute'
        : isHour
        ? 'Hourly limit reached, try again in an hour'
        : 'Monthly usage limit reached, try again next month',
    );
  }
  logRequest('rate_limit_ok', { requestId, userId: user.id });

  // ---- 8. Call Gemini -----------------------------------------------------------
  logRequest('gemini_start', { requestId, userId: user.id, model: cfg.geminiModel });
  try {
    const text = await callGemini(prompt, history, cfg.geminiModel);
    logRequest('gemini_success', { requestId, userId: user.id, responseLength: text.length });
    logRequest('request_end', { requestId, status: 200, durationMs: Date.now() - startTime });
    return new Response(JSON.stringify({ text, model: cfg.geminiModel }), {
      status: 200,
      headers: { ...headers, 'Content-Type': 'application/json' },
    });
  } catch (e) {
    logError('gemini_failed', e, { requestId, userId: user.id });
    const message = e instanceof Error ? e.message : 'Unknown error';
    if (message.includes('Gemini error 429')) {
      logRequest('request_end', {
        requestId,
        status: 502,
        durationMs: Date.now() - startTime,
        error: 'UPSTREAM_RATE_LIMITED',
      });
      return jsonError(502, 'UPSTREAM_RATE_LIMITED', 'The AI provider is busy, try again later');
    }
    logRequest('request_end', {
      requestId,
      status: 502,
      durationMs: Date.now() - startTime,
      error: 'UPSTREAM_ERROR',
    });
    return jsonError(502, 'UPSTREAM_ERROR', 'The AI provider failed, try again later');
  }
});