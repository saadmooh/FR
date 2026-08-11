// ai-proxy — Secure proxy that forwards prompts to the Gemini API.
//
 // Security layers (in order):
 //   1. Supabase Auth: rejects requests without a valid user session.
 //   2. Play Integrity: verifies the client's integrity token against
 //      Google's Play Integrity API and confirms the nonce matches.
 //   3. Rate limiting: per-user minute and monthly windows.
 //
 // Server-side secrets (set with `supabase secrets set`, NEVER in code):
 //   GEMINI_API_KEY              — Google AI (Gemini) API key
 //   GOOGLE_SERVICE_ACCOUNT_JSON — full contents of your GCP service-account
 //                                  JSON (used to call Play Integrity)
 //   EXPECTED_PACKAGE_NAME       — optional, default com.saadmohammed2000.flex_reminder

import { createClient } from 'jsr:@supabase/supabase-js@2';

const SUPABASE_URL = process.env.SUPABASE_URL ?? '';
const SUPABASE_ANON_KEY =
  process.env.SUPABASE_ANON_KEY ?? process.env.SUPABASE_PUBLISHABLE_KEY ?? '';

const GEMINI_API_KEY = process.env.GEMINI_API_KEY ?? '';
const EXPECTED_PACKAGE_NAME =
  process.env.EXPECTED_PACKAGE_NAME ?? 'com.saadmohammed2000.flex_reminder';

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
    // Use defaults if config load fails
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
  configCacheExpiry = now + 60 * 1000; // 60 second TTL
}

// ---------------------------------------------------------------------------
// Rate limiting (database-backed, works across function instances)
// ---------------------------------------------------------------------------

async function checkRateLimit(supabase: ReturnType<typeof createClient>, userId: string): Promise<{ allowed: boolean; period?: 'minute' | 'hour' | 'month' }> {
  await loadConfig(supabase);
  const cfg = configCache!;

  const now = new Date().toISOString();
  const minuteAgo = new Date(Date.now() - 60 * 1000).toISOString();
  const hourAgo = new Date(Date.now() - 60 * 60 * 1000).toISOString();
  const monthStart = new Date();
  monthStart.setDate(1);
  monthStart.setHours(0, 0, 0, 0);
  const monthStartIso = monthStart.toISOString();

  // Use a single RPC call for atomic check-and-increment
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
    // Fail open on DB error to not block legitimate traffic
    return { allowed: true };
  }

  if (!data?.allowed) {
    return { allowed: false, period: data?.period };
  }

  return { allowed: true };
}

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

const encoder = new TextEncoder();

function base64UrlEncode(input: Uint8Array | string): string {
  const bytes = typeof input === 'string' ? encoder.encode(input) : input;
  let binary = '';
  for (let i = 0; i < bytes.length; i++) {
    binary += String.fromCharCode(bytes[i]);
  }
  return btoa(binary).replace(/\+/g, '-').replace(/\//g, '_').replace(/=+$/g, '');
}

function pemToDer(pem: string): Uint8Array {
  const body = pem.replace(/-----BEGIN PRIVATE KEY-----/, '')
    .replace(/-----END PRIVATE KEY-----/, '')
    .replace(/\s+/g, '');
  const binary = atob(body);
  const bytes = new Uint8Array(binary.length);
  for (let i = 0; i < binary.length; i++) {
    bytes[i] = binary.charCodeAt(i);
  }
  return bytes;
}

async function sha256Hex(input: string): Promise<string> {
  const digest = await crypto.subtle.digest('SHA-256', encoder.encode(input));
  return Array.from(new Uint8Array(digest))
    .map((b) => b.toString(16).padStart(2, '0'))
    .join('');
}

async function sha256Base64(input: string): Promise<string> {
  const digest = await crypto.subtle.digest('SHA-256', encoder.encode(input));
  const bytes = new Uint8Array(digest);
  let binary = '';
  for (let i = 0; i < bytes.length; i++) {
    binary += String.fromCharCode(bytes[i]);
  }
  return btoa(binary);
}

function base64ToBytes(input: string): Uint8Array {
  let normalized = input.replace(/-/g, '+').replace(/_/g, '/');
  const padding = normalized.length % 4;
  if (padding) {
    normalized += '='.repeat(4 - padding);
  }
  const binary = atob(normalized);
  const bytes = new Uint8Array(binary.length);
  for (let i = 0; i < binary.length; i++) {
    bytes[i] = binary.charCodeAt(i);
  }
  return bytes;
}

function bytesEqual(a: Uint8Array, b: Uint8Array): boolean {
  if (a.length !== b.length) return false;
  for (let i = 0; i < a.length; i++) {
    if (a[i] !== b[i]) return false;
  }
  return true;
}

function jsonError(status: number, code: string, message: string, diagnostic?: Record<string, unknown>): Response {
  const body: Record<string, unknown> = { error: { code, message } };
  if (diagnostic) {
    body.diagnostic = diagnostic;
  }
  return new Response(
    JSON.stringify(body),
    {
      status,
      headers: { 'Content-Type': 'application/json' },
    },
  );
}

function logRequest(stage: string, data: Record<string, unknown>): void {
  const timestamp = new Date().toISOString();
  const logEntry = {
    timestamp,
    stage,
    function: 'ai-proxy',
    ...data,
  };
  console.log(JSON.stringify(logEntry));
}

function logError(stage: string, error: unknown, context?: Record<string, unknown>): void {
  const timestamp = new Date().toISOString();
  const errorMessage = error instanceof Error ? error.message : String(error);
  const errorStack = error instanceof Error ? error.stack : undefined;
  const logEntry = {
    timestamp,
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
      'authorization, x-client-info, apikey, content-type, x-integrity-token, x-request-nonce',
  });
}

// ---------------------------------------------------------------------------
// Google OAuth2 access token from the service account (RS256 via WebCrypto).
// ---------------------------------------------------------------------------

async function getGoogleAccessToken(): Promise<string> {
  const raw = process.env.GOOGLE_SERVICE_ACCOUNT_JSON;
  if (!raw) {
    throw new Error('GOOGLE_SERVICE_ACCOUNT_JSON is not configured');
  }
  const sa = JSON.parse(raw);
  const now = Math.floor(Date.now() / 1000);

  const header = base64UrlEncode(JSON.stringify({ alg: 'RS256', typ: 'JWT' }));
  const payload = base64UrlEncode(
    JSON.stringify({
      iss: sa.client_email,
      scope: 'https://www.googleapis.com/auth/playintegrity',
      aud: 'https://oauth2.googleapis.com/token',
      iat: now,
      exp: now + 3600,
    }),
  );
  const signingInput = `${header}.${payload}`;

  const key = await crypto.subtle.importKey(
    'pkcs8',
    pemToDer(sa.private_key),
    { name: 'RSASSA-PKCS1-v1_5', hash: 'SHA-256' },
    false,
    ['sign'],
  );
  const signature = new Uint8Array(
    await crypto.subtle.sign('RSASSA-PKCS1-v1_5', key, encoder.encode(signingInput)),
  );

  const jwt = `${signingInput}.${base64UrlEncode(signature)}`;

  const res = await fetch('https://oauth2.googleapis.com/token', {
    method: 'POST',
    headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
    body: new URLSearchParams({
      grant_type: 'urn:ietf:params:oauth:grant-type:jwt-bearer',
      assertion: jwt,
    }),
  });
  const data = await res.json();
  if (!res.ok || !data.access_token) {
    throw new Error(`Failed to obtain Google access token: ${res.status}`);
  }
  return data.access_token;
}

// ---------------------------------------------------------------------------
// Play Integrity verification via Google's decodeIntegrityToken endpoint.
// ---------------------------------------------------------------------------

interface IntegrityPayload {
  requestDetails?: {
    requestHash?: string;
    nonce?: string;
    timestampMillis?: string;
  };
  appIntegrity?: {
    appRecognitionVerdict?: string;
    packageName?: string;
    certificateSha256Digest?: string[];
  };
  deviceIntegrity?: {
    deviceRecognitionVerdict?: string[];
  };
  accountDetails?: {
    appLicensingVerdict?: string;
  };
}

interface DiagnosticData {
  stage: string;
  decodeSuccess: boolean;
  errorType?: string;
  errorMessage?: string;
  requestDetailsPresent?: boolean;
  requestHashPresent?: boolean;
  requestHashMatches?: boolean;
  timestampPresent?: boolean;
  tokenAgeSeconds?: number;
  appIntegrityPresent?: boolean;
  appRecognitionVerdict?: string;
  packageName?: string;
  packageNameMatches?: boolean;
  certificatePresent?: boolean;
  deviceIntegrityPresent?: boolean;
  deviceRecognitionVerdict?: string[];
  licensingVerdict?: string;
  licensingPresent?: boolean;
  failedChecks?: string[];
}

async function verifyIntegrityToken(
  integrityToken: string,
  requestNonce: string,
): Promise<{ passed: boolean; diagnostic: DiagnosticData }> {
  const diagnostic: DiagnosticData = {
    stage: 'decode_integrity_token',
    decodeSuccess: false,
    failedChecks: [],
  };

  try {
    const accessToken = await getGoogleAccessToken();

    const res = await fetch(
      `https://playintegrity.googleapis.com/v1/${EXPECTED_PACKAGE_NAME}:decodeIntegrityToken`,
      {
        method: 'POST',
        headers: {
          Authorization: `Bearer ${accessToken}`,
          'Content-Type': 'application/json',
        },
        body: JSON.stringify({ integrityToken }),
      },
    );

    if (!res.ok) {
      diagnostic.stage = 'backend_decode_failed';
      diagnostic.decodeSuccess = false;
      diagnostic.errorType = 'HTTP_ERROR';
      diagnostic.errorMessage = `Integrity decode failed: ${res.status}`;
      diagnostic.failedChecks!.push('decodeIntegrityTokenHTTPError');
      return { passed: false, diagnostic };
    }

    const data = await res.json();
    const payload: IntegrityPayload = data.tokenPayloadExternal ?? {};
    diagnostic.decodeSuccess = true;

    // A. requestDetails
    diagnostic.requestDetailsPresent = !!payload.requestDetails;
    const nonceFromToken = payload.requestDetails?.nonce;
    diagnostic.requestHashPresent = !!nonceFromToken; // reflects nonce presence for backward compat
    diagnostic.timestampPresent = !!payload.requestDetails?.timestampMillis;

    let nonceMatches = false;
    if (nonceFromToken) {
      try {
        const tokenNonceBytes = base64ToBytes(nonceFromToken);
        const requestNonceBytes = base64ToBytes(requestNonce);
        nonceMatches = bytesEqual(tokenNonceBytes, requestNonceBytes);
      } catch {
        nonceMatches = false;
      }
      if (!nonceMatches) {
        diagnostic.failedChecks!.push('nonceMismatch');
      }
    } else {
      diagnostic.failedChecks!.push('nonceMissing');
    }
    diagnostic.requestHashMatches = nonceMatches; // keep field name for compat

    if (payload.requestDetails?.timestampMillis) {
      const issued = Number(payload.requestDetails.timestampMillis);
      diagnostic.tokenAgeSeconds = Math.floor((Date.now() - issued) / 1000);
    } else {
      diagnostic.failedChecks!.push('timestampMissing');
    }

    // B. appIntegrity
    diagnostic.appIntegrityPresent = !!payload.appIntegrity;
    diagnostic.appRecognitionVerdict = payload.appIntegrity?.appRecognitionVerdict ?? 'MISSING';
    diagnostic.packageName = payload.appIntegrity?.packageName ?? 'MISSING';
    diagnostic.packageNameMatches = payload.appIntegrity?.packageName === EXPECTED_PACKAGE_NAME;
    diagnostic.certificatePresent = !!(payload.appIntegrity?.certificateSha256Digest && payload.appIntegrity.certificateSha256Digest.length > 0);

    if (!diagnostic.packageNameMatches) {
      diagnostic.failedChecks!.push('packageNameMismatch');
    }

    if (payload.appIntegrity?.appRecognitionVerdict !== 'PLAY_RECOGNIZED') {
      diagnostic.failedChecks!.push(`appRecognitionVerdict=${payload.appIntegrity?.appRecognitionVerdict ?? 'MISSING'}`);
    }

    // C. deviceIntegrity
    diagnostic.deviceIntegrityPresent = !!payload.deviceIntegrity;
    diagnostic.deviceRecognitionVerdict = payload.deviceIntegrity?.deviceRecognitionVerdict ?? [];

    // D. licensing
    diagnostic.licensingPresent = !!payload.accountDetails;
    diagnostic.licensingVerdict = payload.accountDetails?.appLicensingVerdict ?? 'MISSING';

    diagnostic.stage = 'backend_verification';

    // 1. Nonce must match the token's nonce.
    if (!diagnostic.requestHashMatches) {
      return { passed: false, diagnostic };
    }

    // 2. Replay protection: token must be fresh (issued < 5 minutes ago).
    if (!payload.requestDetails?.timestampMillis || Date.now() - Number(payload.requestDetails.timestampMillis) > 5 * 60 * 1000) {
      diagnostic.failedChecks!.push('tokenExpired');
      return { passed: false, diagnostic };
    }

    // 3. App must be recognized by Google Play.
    if (payload.appIntegrity?.appRecognitionVerdict !== 'PLAY_RECOGNIZED') {
      return { passed: false, diagnostic };
    }
    if (payload.appIntegrity?.packageName !== EXPECTED_PACKAGE_NAME) {
      return { passed: false, diagnostic };
    }

    // 4. Device must meet integrity requirements.
    const deviceVerdicts = payload.deviceIntegrity?.deviceRecognitionVerdict ?? [];
    if (!deviceVerdicts.includes('MEETS_DEVICE_INTEGRITY')) {
      diagnostic.failedChecks!.push('deviceIntegrityFailed');
      return { passed: false, diagnostic };
    }

    return { passed: true, diagnostic };
  } catch (e) {
    diagnostic.stage = 'backend_decode_failed';
    diagnostic.decodeSuccess = false;
    diagnostic.errorType = e instanceof Error ? e.constructor.name : 'UNKNOWN_ERROR';
    diagnostic.errorMessage = e instanceof Error ? e.message : 'Unknown error during verification';
    diagnostic.failedChecks!.push('decodeException');
    return { passed: false, diagnostic };
  }
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
    logRequest('request_end', { requestId, status: 405, durationMs: Date.now() - startTime, error: 'METHOD_NOT_ALLOWED' });
    return jsonError(405, 'METHOD_NOT_ALLOWED', 'Only POST is allowed');
  }

  // ---- 1. Supabase Auth ----------------------------------------------------
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
    logRequest('request_end', { requestId, status: 401, durationMs: Date.now() - startTime, error: 'UNAUTHENTICATED' });
    return jsonError(401, 'UNAUTHENTICATED', 'You must be signed in first');
  }
  logRequest('auth_success', { requestId, userId: user.id });

  // Load config from database (cached)
  await loadConfig(supabase);
  const cfg = configCache!;

  // ---- 2. Play Integrity ----------------------------------------------------
  const integrityToken = req.headers.get('X-Integrity-Token');
  const requestNonce = req.headers.get('X-Request-Nonce');
  const isDebugBuild = req.headers.get('X-Debug-Build') === 'true';

  logRequest('integrity_start', { requestId, userId: user.id, isDebugBuild, hasToken: !!integrityToken, hasNonce: !!requestNonce });

  if (cfg.allowDebugBypass && isDebugBuild) {
    logRequest('integrity_bypass', { requestId, userId: user.id, reason: 'debug_build' });
  } else {
    if (!integrityToken || !requestNonce) {
      logError('integrity_missing', new Error('Missing integrity token or nonce'), { requestId, userId: user.id });
      logRequest('request_end', { requestId, status: 403, durationMs: Date.now() - startTime, error: 'INTEGRITY_MISSING' });
      return jsonError(
        403,
        'INTEGRITY_MISSING',
        'Integrity token and nonce are required',
        { stage: 'request_validation', decodeSuccess: false, errorMessage: 'Missing integrity token or nonce' },
      );
    }

    const { passed, diagnostic } = await verifyIntegrityToken(integrityToken, requestNonce);
    logRequest('integrity_result', { requestId, userId: user.id, passed, stage: diagnostic.stage, failedChecks: diagnostic.failedChecks });

    if (!passed) {
      logError('integrity_failed', new Error('Integrity check failed'), { requestId, userId: user.id, diagnostic });
      logRequest('request_end', { requestId, status: 403, durationMs: Date.now() - startTime, error: 'INTEGRITY_FAILED' });
      return jsonError(
        403,
        'INTEGRITY_FAILED',
        'App integrity check failed, update the app to the latest version',
        diagnostic,
      );
    }
  }

  // ---- 3. Rate limiting -----------------------------------------------------
  logRequest('rate_limit_start', { requestId, userId: user.id });
  const limit = await checkRateLimit(supabase, user.id);
  if (!limit.allowed) {
    logError('rate_limit_exceeded', new Error(`Rate limit exceeded: ${limit.period}`), { requestId, userId: user.id, period: limit.period });
    logRequest('request_end', { requestId, status: 429, durationMs: Date.now() - startTime, error: `RATE_LIMIT_${limit.period?.toUpperCase()}` });
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

  // ---- 4. Parse body --------------------------------------------------------
  logRequest('body_parse_start', { requestId, userId: user.id });
  let body: { prompt?: unknown; conversationHistory?: unknown };
  try {
    body = await req.json();
  } catch (e) {
    logError('body_parse_failed', e, { requestId, userId: user.id });
    logRequest('request_end', { requestId, status: 400, durationMs: Date.now() - startTime, error: 'INVALID_BODY' });
    return jsonError(400, 'INVALID_BODY', 'Request body must be valid JSON');
  }

  const prompt = typeof body.prompt === 'string' ? body.prompt.trim() : '';
  if (!prompt) {
    logRequest('request_end', { requestId, status: 400, durationMs: Date.now() - startTime, error: 'EMPTY_PROMPT' });
    return jsonError(400, 'EMPTY_PROMPT', 'Prompt cannot be empty');
  }
  if (prompt.length > 4000) {
    logRequest('request_end', { requestId, status: 400, durationMs: Date.now() - startTime, error: 'PROMPT_TOO_LONG' });
    return jsonError(400, 'PROMPT_TOO_LONG', 'Prompt is too long (max 4000 chars)');
  }

  const history: ChatTurn[] = Array.isArray(body.conversationHistory)
    ? (body.conversationHistory as ChatTurn[])
        .filter(
          (t) =>
            t && typeof t.content === 'string' &&
            (t.role === 'user' || t.role === 'assistant'),
        )
        .slice(-cfg.maxHistoryTurns)
    : [];
  logRequest('body_parse_ok', { requestId, userId: user.id, promptLength: prompt.length, historyTurns: history.length });

  // ---- 5. Call Gemini -------------------------------------------------------
  logRequest('gemini_start', { requestId, userId: user.id, model: cfg.geminiModel });
  try {
    const text = await callGemini(prompt, history, cfg.geminiModel);
    logRequest('gemini_success', { requestId, userId: user.id, responseLength: text.length });
    logRequest('request_end', { requestId, status: 200, durationMs: Date.now() - startTime });
    return new Response(
      JSON.stringify({ text, model: cfg.geminiModel }),
      { status: 200, headers: { ...headers, 'Content-Type': 'application/json' } },
    );
  } catch (e) {
    logError('gemini_failed', e, { requestId, userId: user.id });
    const message = e instanceof Error ? e.message : 'Unknown error';
    if (message.includes('Gemini error 429')) {
      logRequest('request_end', { requestId, status: 502, durationMs: Date.now() - startTime, error: 'UPSTREAM_RATE_LIMITED' });
      return jsonError(
        502,
        'UPSTREAM_RATE_LIMITED',
        'The AI provider is busy, try again later',
      );
    }
    logRequest('request_end', { requestId, status: 502, durationMs: Date.now() - startTime, error: 'UPSTREAM_ERROR' });
    return jsonError(502, 'UPSTREAM_ERROR', 'The AI provider failed, try again later');
  }
});
