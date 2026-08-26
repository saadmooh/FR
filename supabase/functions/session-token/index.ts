// session-token — Issues a short-lived (60 min) HS256 session JWT proving an
// active Pro entitlement, after three gates:
//   1. Firebase Auth: the Authorization header must carry a valid Firebase ID
//      token (verified against Google's public keys; `sub` = Firebase UID,
//      the same identifier the app passes to Purchases.logIn).
//   2. Play Integrity: reuses the exact verification pipeline from
//      _shared/integrity.ts (nonce match, freshness, package + cert pinning,
//      device + licensing verdicts).
//   3. Entitlement: the caller's row in `entitlements` must have status
//      'active' with no expired expires_at.
//
// The nonce is single-use (claimed in used_nonces via service_role), so each
// session token requires a fresh integrity token — replay-proof.
//
// Deploy with: supabase functions deploy session-token --no-verify-jwt
// (the Authorization header carries a FIREBASE token, which Supabase's
// platform verifier would reject before our handler runs).
//
// Secrets (set with `supabase secrets set`, NEVER in code):
//   FIREBASE_PROJECT_ID     — your Firebase project id
//   SESSION_TOKEN_SECRET    — random 48+ byte secret, e.g. openssl rand -base64 48
//   GOOGLE_SERVICE_ACCOUNT_JSON / EXPECTED_PACKAGE_NAME / EXPECTED_CERT_SHA256
//                           — same Play Integrity config as ai-proxy

import { createClient } from 'jsr:@supabase/supabase-js@2';

import { verifyIntegrityToken } from '../_shared/integrity.ts';
import { verifyFirebaseIdToken } from '../_shared/firebase_verify.ts';
import { signSessionToken } from '../_shared/session_jwt.ts';

const SUPABASE_URL = Deno.env.get('SUPABASE_URL') ?? '';
const SUPABASE_SERVICE_ROLE_KEY = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') ?? '';
const SESSION_TOKEN_SECRET = Deno.env.get('SESSION_TOKEN_SECRET') ?? '';
const REVENUECAT_SECRET_API_KEY = Deno.env.get('REVENUECAT_SECRET_API_KEY') ?? '';
const REVENUECAT_PROJECT_ID = Deno.env.get('REVENUECAT_PROJECT_ID') ?? '';
const PREMIUM_ENTITLEMENT_ID = 'pro';
const SESSION_TTL_SECONDS = 60 * 60;

function jsonError(status: number, code: string, message: string): Response {
  return new Response(JSON.stringify({ error: { code, message } }), {
    status,
    headers: { 'Content-Type': 'application/json' },
  });
}

function cors(): Headers {
  return new Headers({
    'Access-Control-Allow-Origin': '*',
    'Access-Control-Allow-Methods': 'POST, OPTIONS',
    'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
  });
}

function log(stage: string, data: Record<string, unknown>): void {
  console.log(JSON.stringify({ timestamp: new Date().toISOString(), function: 'session-token', stage, ...data }));
}

function logError(stage: string, error: unknown, data: Record<string, unknown> = {}): void {
  const message = error instanceof Error ? error.message : String(error);
  console.error(JSON.stringify({
    timestamp: new Date().toISOString(),
    function: 'session-token',
    stage,
    level: 'ERROR',
    error: message,
    ...data,
  }));
}

/**
 * Atomically claims a nonce (primary-key conflict => replay). Non-replay DB
 * errors fail open, mirroring ai-proxy's claimNonce behavior.
 */
async function claimNonce(
  admin: ReturnType<typeof createClient>,
  nonce: string,
): Promise<boolean> {
  // user_id stays null here: it is UUID-typed while our identity is the
  // Firebase UID. Uniqueness on `nonce` is what enforces replay protection.
  const { error } = await admin.from('used_nonces').insert({ nonce });
  if (!error) return true;
  if ((error as { code?: string }).code === '23505') return false;
  logError('claim_nonce_db_error', error, { code: (error as { code?: string }).code });
  return true;
}

Deno.serve(async (req: Request) => {
  const headers = cors();

  if (req.method === 'OPTIONS') {
    return new Response(null, { status: 204, headers });
  }
  if (req.method !== 'POST') {
    return jsonError(405, 'METHOD_NOT_ALLOWED', 'Only POST is allowed');
  }

  // ---- 1. Firebase authentication ------------------------------------------
  let firebaseUid: string;
  try {
    const ctx = await verifyFirebaseIdToken(req.headers.get('Authorization'));
    if (!ctx) {
      log('auth_failed', {});
      return jsonError(401, 'UNAUTHENTICATED', 'Valid Firebase ID token required');
    }
    firebaseUid = ctx.uid;
  } catch (e) {
    logError('auth_error', e);
    return jsonError(401, 'UNAUTHENTICATED', 'Token verification failed');
  }
  log('auth_success', { userId: firebaseUid });

  if (!SESSION_TOKEN_SECRET) {
    logError('server_not_configured', new Error('SESSION_TOKEN_SECRET is not set'));
    return jsonError(500, 'SERVER_NOT_CONFIGURED', 'Session signing is not configured');
  }

  // ---- 2. Parse body ---------------------------------------------------------
  let body: { integrityToken?: unknown; nonce?: unknown };
  try {
    body = await req.json();
  } catch {
    return jsonError(400, 'INVALID_BODY', 'Request body must be valid JSON');
  }
  const integrityToken = typeof body.integrityToken === 'string' ? body.integrityToken : '';
  const nonce = typeof body.nonce === 'string' ? body.nonce : '';
  if (!integrityToken || !nonce) {
    return jsonError(400, 'INTEGRITY_MISSING', 'integrityToken and nonce are required');
  }

  // ---- 3. Play Integrity (same pipeline as ai-proxy) ------------------------
  const { passed, diagnostic } = await verifyIntegrityToken(integrityToken, nonce, nonce);
  log('integrity_result', { userId: firebaseUid, passed, failedChecks: diagnostic.failedChecks });
  if (!passed) {
    return jsonError(403, 'INTEGRITY_FAILED', 'App integrity check failed');
  }

  // ---- 4. Nonce replay protection --------------------------------------------
  const admin = createClient(SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY, {
    auth: { persistSession: false },
  });

  const claimed = await claimNonce(admin, nonce);
  if (!claimed) {
    log('nonce_replay', { userId: firebaseUid });
    return jsonError(403, 'NONCE_REPLAY', 'This request has already been processed');
  }

  // ---- 5. Entitlement check ----------------------------------------------------
  const { data: entitlement, error: entError } = await admin
    .from('entitlements')
    .select('status, expires_at')
    .eq('user_id', firebaseUid)
    .maybeSingle();

  if (entError) {
    logError('entitlement_query_failed', entError, { userId: firebaseUid });
    return jsonError(500, 'DB_ERROR', 'Failed to verify subscription');
  }

  let isActive =
    !!entitlement &&
    entitlement.status === 'active' &&
    (!entitlement.expires_at || new Date(entitlement.expires_at).getTime() > Date.now());

  // Fallback: the webhook row may be missing (events not yet delivered, new
  // install of an existing subscriber, delivery lag). Ask RevenueCat directly
  // (V2 API — the secret key is V2-scoped) and self-heal by writing the row
  // so future checks hit the table.
  if (!isActive && REVENUECAT_SECRET_API_KEY && REVENUECAT_PROJECT_ID) {
    try {
      const encUid = encodeURIComponent(firebaseUid);
      const base = `https://api.revenuecat.com/v2/projects/${REVENUECAT_PROJECT_ID}/customers/${encUid}`;
      const res = await fetch(`${base}/active_entitlements`, {
        headers: { Authorization: `Bearer ${REVENUECAT_SECRET_API_KEY}` },
      });
      if (res.ok) {
        const data = await res.json();
        const items = data?.items ?? [];
        const pro = items.find(
          (e: { lookup_key?: string; entitlement_id?: string }) =>
            e.lookup_key === PREMIUM_ENTITLEMENT_ID ||
            e.entitlement_id === PREMIUM_ENTITLEMENT_ID,
        );
        isActive = !!pro;
        if (isActive) {
          log('rc_api_fallback_hit', {
            userId: firebaseUid,
            entitlementId: pro?.entitlement_id ?? null,
          });
          await admin.from('entitlements').upsert(
            {
              user_id: firebaseUid,
              product_id: null,
              entitlement_id: PREMIUM_ENTITLEMENT_ID,
              status: 'active',
              expires_at: null,
              updated_at: new Date().toISOString(),
            },
            { onConflict: 'user_id' },
          );
        }
      } else if (res.status !== 404) {
        logError('rc_api_fallback_http_error', new Error(`RC API ${res.status}`), {
          userId: firebaseUid,
          status: res.status,
        });
      }
    } catch (e) {
      logError('rc_api_fallback_failed', e, { userId: firebaseUid });
    }
  }

  if (!isActive) {
    log('entitlement_rejected', {
      userId: firebaseUid,
      status: entitlement?.status ?? 'missing_row',
      expiresAt: entitlement?.expires_at ?? null,
    });
    return jsonError(403, 'SUBSCRIPTION_NOT_ACTIVE', 'An active Pro subscription is required');
  }

  // ---- 6. Issue short-lived session JWT ---------------------------------------
  const { token, expiresIn } = await signSessionToken(firebaseUid, SESSION_TOKEN_SECRET, SESSION_TTL_SECONDS);
  log('session_token_issued', { userId: firebaseUid, expiresIn });
  return new Response(JSON.stringify({ token }), {
    status: 200,
    headers: { ...headers, 'Content-Type': 'application/json' },
  });
});
