// ai-proxy — Secure proxy that forwards prompts to the Gemini API.
//
// Security layers (in order):
//   1. Supabase Auth: rejects requests without a valid user session.
//   2. Body parsing: prompt/history/timestamp are read early because the
//      integrity + nonce-binding checks below need them.
//   3. Play Integrity: verifies the client's integrity token against
//      Google's Play Integrity API, confirms the nonce matches, AND now
//      pins the signing certificate so only your real signed APK passes.
//   4. Request binding: the nonce must be derived from THIS request's
//      content (prompt + user + timestamp), not just present — this stops
//      a token/nonce pair captured from one request being replayed with a
//      different prompt.
//   5. Nonce replay protection: each nonce can be claimed (used) exactly
//      once, stored in the `used_nonces` table, closing the "token farm"
//      window where a valid pair is reused multiple times within its
//      5-minute validity.
//   6. Rate limiting: per-user minute/hour/month windows.
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
//
// Database migration required (see used_nonces table at bottom of this file
// as a comment, or run separately):
//   create table used_nonces (
//     nonce text primary key,
//     user_id uuid not null,
//     used_at timestamptz not null default now()
//   );
//   create index used_nonces_used_at_idx on used_nonces (used_at);

import { createClient } from 'jsr:@supabase/supabase-js@2';

const SUPABASE_URL = Deno.env.get('SUPABASE_URL') ?? '';
const SUPABASE_ANON_KEY =
  Deno.env.get('SUPABASE_ANON_KEY') ?? Deno.env.get('SUPABASE_PUBLISHABLE_KEY') ?? '';

const GEMINI_API_KEY = Deno.env.get('GEMINI_API_KEY') ?? '';
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
  const body = pem
    .replace(/-----BEGIN PRIVATE KEY-----/, '')
    .replace(/-----END PRIVATE KEY-----/, '')
    .replace(/\s+/g, '');
  const binary = atob(body);
  const bytes = new Uint8Array(binary.length);
  for (let i = 0; i < binary.length; i++) {
    bytes[i] = binary.charCodeAt(i);
  }
  return bytes;
}

async function sha256Base64(input: string): Promise<string> {
  const digest = await crypto.subtle.digest('SHA-256', encoder.encode(input));
  // Use the first 30 bytes (a multiple of 3) so the Base64 is a clean 40-char
  // string with no padding. Must match the client's generateNonce().
  const bytes = new Uint8Array(digest).slice(0, 30);
  let binary = '';
  for (let i = 0; i < bytes.length; i++) {
    binary += String.fromCharCode(bytes[i]);
  }
  // URL-safe Base64 (alphabet A-Za-z0-9-_), no padding — matches the client
  // nonce exactly (string compare) and what Play Services expects.
  return btoa(binary).replace(/\+/g, '-').replace(/\//g, '_').replace(/=+$/, '');
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
      'authorization, x-client-info, apikey, content-type, x-integrity-token, x-request-nonce',
  });
}

// ---------------------------------------------------------------------------
// Google OAuth2 access token from the service account (RS256 via WebCrypto).
// ---------------------------------------------------------------------------

async function getGoogleAccessToken(): Promise<string> {
  const raw = Deno.env.get('GOOGLE_SERVICE_ACCOUNT_JSON');
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
  certificateMatches?: boolean;
  deviceIntegrityPresent?: boolean;
  deviceRecognitionVerdict?: string[];
  licensingVerdict?: string;
  licensingPresent?: boolean;
  failedChecks?: string[];
  [key: string]: unknown;
}

async function verifyIntegrityToken(
  integrityToken: string,
  requestNonce: string,
  expectedNonceHash: string,
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

    // A. requestDetails / nonce
    diagnostic.requestDetailsPresent = !!payload.requestDetails;
    const nonceFromToken = payload.requestDetails?.nonce;
    diagnostic.requestHashPresent = !!nonceFromToken;
    diagnostic.timestampPresent = !!payload.requestDetails?.timestampMillis;

    let nonceMatches = false;
    if (nonceFromToken) {
      try {
        const tokenNonceBytes = base64ToBytes(nonceFromToken);
        const requestNonceBytes = base64ToBytes(requestNonce);
        const expectedNonceBytes = base64ToBytes(expectedNonceHash);
        // The token nonce must equal the request nonce OR the expected hash
        // derived from the request. Comparing decoded bytes makes this
        // resilient to Base64 encoding differences (standard vs url-safe,
        // padding) between the client, Play Services and Google's echo.
        nonceMatches =
          bytesEqual(tokenNonceBytes, requestNonceBytes) ||
          bytesEqual(tokenNonceBytes, expectedNonceBytes);
      } catch {
        nonceMatches = false;
      }
      if (!nonceMatches) {
        diagnostic.failedChecks!.push('nonceMismatch');
      }
    } else {
      diagnostic.failedChecks!.push('nonceMissing');
    }
    diagnostic.requestHashMatches = nonceMatches;

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

    const certDigests = payload.appIntegrity?.certificateSha256Digest ?? [];
    diagnostic.certificatePresent = certDigests.length > 0;

    // --- Certificate pinning ---------------------------------------------
    const certificateMatches =
      EXPECTED_CERT_HASHES.length > 0 && certDigests.some((d) => EXPECTED_CERT_HASHES.includes(d));
    diagnostic.certificateMatches = certificateMatches;

    if (EXPECTED_CERT_HASHES.length === 0) {
      // Misconfiguration guard: don't silently skip pinning, make it loud
      // in logs so it gets fixed, without blocking traffic if you haven't
      // rolled this out yet. Once EXPECTED_CERT_SHA256 is set, this branch
      // stops firing and pinning becomes mandatory (see check below).
      diagnostic.failedChecks!.push('certPinningNotConfigured');
    } else if (!certificateMatches) {
      diagnostic.failedChecks!.push('certificateMismatch');
    }

    if (!diagnostic.packageNameMatches) {
      diagnostic.failedChecks!.push('packageNameMismatch');
    }

    if (payload.appIntegrity?.appRecognitionVerdict !== 'PLAY_RECOGNIZED') {
      diagnostic.failedChecks!.push(
        `appRecognitionVerdict=${payload.appIntegrity?.appRecognitionVerdict ?? 'MISSING'}`,
      );
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
    if (
      !payload.requestDetails?.timestampMillis ||
      Date.now() - Number(payload.requestDetails.timestampMillis) > 5 * 60 * 1000
    ) {
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

    // 4. Certificate must match your known signing key(s).
    //    Enforced once EXPECTED_CERT_SHA256 is configured — set this secret
    //    before relying on it, otherwise this check is a no-op (logged as
    //    certPinningNotConfigured above, but does not block requests).
    if (EXPECTED_CERT_HASHES.length > 0 && !certificateMatches) {
      return { passed: false, diagnostic };
    }

    // 5. Device must meet integrity requirements.
    //    We intentionally cap at MEETS_DEVICE_INTEGRITY (NOT STRONG).
    //    MEETS_STRONG_INTEGRITY depends on the device's hardware-backed
    //    attestation capabilities (e.g. StrongBox / keymaster), which many
    //    legitimate, Play-distributed devices do not support regardless of
    //    how the app was installed. Requiring STRONG would wrongly block
    //    real users on older / lower-end hardware, not just attackers.
    const deviceVerdicts = payload.deviceIntegrity?.deviceRecognitionVerdict ?? [];
    if (!deviceVerdicts.includes('MEETS_DEVICE_INTEGRITY')) {
      diagnostic.failedChecks!.push('deviceIntegrityFailed');
      return { passed: false, diagnostic };
    }

    // 6. Licensing — the real signal that the app was obtained through a
    //    legitimate Google Play account (even when free). This — not the
    //    deviceIntegrity hardware level — is what distinguishes a
    //    sideloaded / locally-built APK from a genuine Play install.
    const licensingVerdict = payload.accountDetails?.appLicensingVerdict;
    diagnostic.licensingVerdict = licensingVerdict ?? 'MISSING';
    diagnostic.licensingPresent = !!payload.accountDetails;
    if (licensingVerdict === 'UNEVALUATED') {
      // Account not linked as a Play tester / licensed user. Often a real
      // user who simply isn't registered as a tester in Play Console (common
      // in internal / closed testing) — NOT necessarily a tampering attempt.
      diagnostic.failedChecks!.push('licensingUnevaluated');
      return { passed: false, diagnostic };
    }
    if (licensingVerdict !== 'LICENSED') {
      // UNLICENSED (or MISSING) — app not obtained through a licensed Play
      // account. This is the genuine anti-tamper signal.
      diagnostic.failedChecks!.push('licensingNotVerified');
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

  // ---- 6. Rate limiting -------------------------------------------------------
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

  // ---- 7. Call Gemini -----------------------------------------------------------
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