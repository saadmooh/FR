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
//   GEMINI_MODEL                — optional, default gemini-3.1-flash-lite
//   EXPECTED_PACKAGE_NAME       — optional, default com.saadmohammed2000.flex_reminder
//   RATE_LIMIT_PER_MINUTE       — optional, default 10
//   RATE_LIMIT_PER_MONTH        — optional, default 500

import { createClient } from 'jsr:@supabase/supabase-js@2';

const SUPABASE_URL = process.env.SUPABASE_URL ?? '';
const SUPABASE_ANON_KEY =
  process.env.SUPABASE_ANON_KEY ?? process.env.SUPABASE_PUBLISHABLE_KEY ?? '';

const GEMINI_API_KEY = process.env.GEMINI_API_KEY ?? '';
const GEMINI_MODEL = process.env.GEMINI_MODEL ?? 'gemini-3.1-flash-lite';
const EXPECTED_PACKAGE_NAME =
  process.env.EXPECTED_PACKAGE_NAME ?? 'com.saadmohammed2000.flex_reminder';
const RATE_LIMIT_PER_MINUTE = Number(process.env.RATE_LIMIT_PER_MINUTE ?? 10);
const RATE_LIMIT_PER_MONTH = Number(process.env.RATE_LIMIT_PER_MONTH ?? 500);
const MAX_HISTORY_TURNS = 20;
const ALLOW_DEBUG_BYPASS = process.env.ALLOW_DEBUG_BYPASS === 'true';

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
// Rate limiting (best-effort in-memory; works for a single function instance).
// ---------------------------------------------------------------------------

const minuteWindows = new Map<string, number[]>();
const monthlyWindows = new Map<string, string>();

function checkRateLimit(userId: string): { allowed: boolean; period?: 'minute' | 'month' } {
  const now = Date.now();

  // Minute window
  const minuteKey = userId;
  const recent = (minuteWindows.get(minuteKey) ?? []).filter(
    (t) => now - t < 60 * 1000,
  );
  if (recent.length >= RATE_LIMIT_PER_MINUTE) {
    return { allowed: false, period: 'minute' };
  }
  recent.push(now);
  minuteWindows.set(minuteKey, recent);

  // Monthly window
  const month = new Date().toISOString().slice(0, 7); // YYYY-MM
  const monthKey = `${userId}:${month}`;
  const currentMonth = monthlyWindows.get(monthKey);
  if (currentMonth && currentMonth !== month) {
    monthlyWindows.set(monthKey, month);
  }
  const monthlyCount = [...monthlyWindows.keys()].filter(
    (k) => k === monthKey,
  ).length;
  if (monthlyCount >= RATE_LIMIT_PER_MONTH) {
    return { allowed: false, period: 'month' };
  }
  if (!monthlyWindows.has(monthKey)) {
    monthlyWindows.set(monthKey, month);
  }

  return { allowed: true };
}

// ---------------------------------------------------------------------------
// Gemini call
// ---------------------------------------------------------------------------

interface ChatTurn {
  role: string;
  content: string;
}

async function callGemini(prompt: string, history: ChatTurn[]): Promise<string> {
  const contents = history.map((turn) => ({
    role: turn.role === 'assistant' ? 'model' : 'user',
    parts: [{ text: turn.content }],
  }));
  contents.push({ role: 'user', parts: [{ text: prompt }] });

  const res = await fetch(
    `https://generativelanguage.googleapis.com/v1beta/models/${GEMINI_MODEL}:generateContent?key=${GEMINI_API_KEY}`,
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
  const headers = cors();
  if (req.method === 'OPTIONS') {
    return new Response(null, { status: 204, headers });
  }
  if (req.method !== 'POST') {
    return jsonError(405, 'METHOD_NOT_ALLOWED', 'Only POST is allowed');
  }

  // ---- 1. Supabase Auth ----------------------------------------------------
  const authHeader = req.headers.get('Authorization') ?? '';
  const supabase = createClient(SUPABASE_URL, SUPABASE_ANON_KEY, {
    global: { headers: { Authorization: authHeader } },
  });
  const {
    data: { user },
    error: authError,
  } = await supabase.auth.getUser();

  if (authError || !user) {
    return jsonError(401, 'UNAUTHENTICATED', 'You must be signed in first');
  }

  // ---- 2. Play Integrity ----------------------------------------------------
  const integrityToken = req.headers.get('X-Integrity-Token');
  const requestNonce = req.headers.get('X-Request-Nonce');
  const isDebugBuild = req.headers.get('X-Debug-Build') === 'true';

  if (ALLOW_DEBUG_BYPASS && isDebugBuild) {
    console.log('Debug build detected, skipping integrity check');
  } else {
    if (!integrityToken || !requestNonce) {
      return jsonError(
        403,
        'INTEGRITY_MISSING',
        'Integrity token and nonce are required',
        { stage: 'request_validation', decodeSuccess: false, errorMessage: 'Missing integrity token or nonce' },
      );
    }

    const { passed, diagnostic } = await verifyIntegrityToken(integrityToken, requestNonce);
    if (!passed) {
      return jsonError(
        403,
        'INTEGRITY_FAILED',
        'App integrity check failed, update the app to the latest version',
        diagnostic,
      );
    }
  }

  // ---- 3. Rate limiting -----------------------------------------------------
  const limit = checkRateLimit(user.id);
  if (!limit.allowed) {
    const isMinute = limit.period === 'minute';
    return jsonError(
      429,
      isMinute ? 'RATE_LIMIT_MINUTE' : 'RATE_LIMIT_MONTH',
      isMinute
        ? 'Rate limit exceeded, try again in a minute'
        : 'Monthly usage limit reached, try again next month',
    );
  }

  // ---- 4. Parse body --------------------------------------------------------
  let body: { prompt?: unknown; conversationHistory?: unknown };
  try {
    body = await req.json();
  } catch {
    return jsonError(400, 'INVALID_BODY', 'Request body must be valid JSON');
  }

  const prompt = typeof body.prompt === 'string' ? body.prompt.trim() : '';
  if (!prompt) {
    return jsonError(400, 'EMPTY_PROMPT', 'Prompt cannot be empty');
  }
  if (prompt.length > 4000) {
    return jsonError(400, 'PROMPT_TOO_LONG', 'Prompt is too long (max 4000 chars)');
  }

  const history: ChatTurn[] = Array.isArray(body.conversationHistory)
    ? (body.conversationHistory as ChatTurn[])
        .filter(
          (t) =>
            t && typeof t.content === 'string' &&
            (t.role === 'user' || t.role === 'assistant'),
        )
        .slice(-MAX_HISTORY_TURNS)
    : [];

  // ---- 5. Call Gemini -------------------------------------------------------
  try {
    const text = await callGemini(prompt, history);
    return new Response(
      JSON.stringify({ text, model: GEMINI_MODEL }),
      { status: 200, headers: { ...headers, 'Content-Type': 'application/json' } },
    );
  } catch (e) {
    console.error('Upstream error:', e);
    const message = e instanceof Error ? e.message : 'Unknown error';
    if (message.includes('Gemini error 429')) {
      return jsonError(
        502,
        'UPSTREAM_RATE_LIMITED',
        'The AI provider is busy, try again later',
      );
    }
    return jsonError(502, 'UPSTREAM_ERROR', 'The AI provider failed, try again later');
  }
});
