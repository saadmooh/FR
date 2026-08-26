// revenuecat-webhook — Receives purchase lifecycle events from RevenueCat and
// upserts the user's entitlement state into the `entitlements` table.
//
// Deploy with: supabase functions deploy revenuecat-webhook --no-verify-jwt
// (the Authorization header carries the RevenueCat webhook secret, not a
// Supabase JWT, so platform JWT verification must be disabled).
//
// Secrets (set with `supabase secrets set`, NEVER in code):
//   REVENUECAT_WEBHOOK_SECRET — exact value of RevenueCat's Authorization
//                               header configured in the dashboard.
//
// Identifier note: the app calls Purchases.logIn(firebaseUid), so
// event.app_user_id is a Firebase UID (not a UUID). Anonymous RevenueCat
// users ("$RCAnonymousID...") are ignored with 200 — that is expected, not
// an error. All writes use the service_role client to bypass RLS.

import { createClient } from 'jsr:@supabase/supabase-js@2';

const SUPABASE_URL = Deno.env.get('SUPABASE_URL') ?? '';
const SUPABASE_SERVICE_ROLE_KEY = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') ?? '';

interface RcEvent {
  type?: string;
  app_user_id?: string | null;
  product_id?: string | null;
  entitlement_ids?: string[] | null;
  expiration_at_ms?: number | null;
  store?: string | null;
}

interface RcPayload {
  event?: RcEvent;
}

/** Maps a RevenueCat event type to an entitlement status, or null to ignore. */
function statusForEventType(type: string): string | null {
  switch (type) {
    case 'INITIAL_PURCHASE':
    case 'RENEWAL':
    case 'PRODUCT_CHANGE':
    case 'UNCANCELLATION':
    case 'REFUND_REVERSED':
      return 'active';
    case 'EXPIRATION':
      return 'expired';
    // Cancellation does not revoke access immediately — access continues
    // until expires_at, so the row stays active with its expiry date.
    case 'CANCELLATION':
      return 'active';
    case 'BILLING_ISSUE':
      return 'billing_issue';
    default:
      // TEST, TRANSFER, SUBSCRIBER_ALIAS, etc. — acknowledged without changes
      // so RevenueCat does not retry them endlessly.
      return null;
  }
}

function constantTimeEqual(a: string, b: string): boolean {
  const ab = new TextEncoder().encode(a);
  const bb = new TextEncoder().encode(b);
  let diff = ab.length ^ bb.length;
  for (let i = 0; i < Math.max(ab.length, bb.length); i++) {
    diff |= (ab[i] ?? 0) ^ (bb[i] ?? 0);
  }
  return diff === 0;
}

Deno.serve(async (req: Request) => {
  if (req.method !== 'POST') {
    return new Response(JSON.stringify({ error: 'method_not_allowed' }), {
      status: 405,
      headers: { 'Content-Type': 'application/json' },
    });
  }

  // ---- 1. Authorization check — fail fast before touching the body --------
  const secret = Deno.env.get('REVENUECAT_WEBHOOK_SECRET');
  if (!secret) {
    console.error(JSON.stringify({
      level: 'ERROR',
      function: 'revenuecat-webhook',
      error: 'REVENUECAT_WEBHOOK_SECRET is not configured',
    }));
    return new Response(JSON.stringify({ error: 'server_not_configured' }), {
      status: 500,
      headers: { 'Content-Type': 'application/json' },
    });
  }
  if (!constantTimeEqual(req.headers.get('Authorization')?.trim() ?? '', secret)) {
    console.error(JSON.stringify({
      level: 'ERROR',
      function: 'revenuecat-webhook',
      error: 'authorization_mismatch',
    }));
    return new Response(JSON.stringify({ error: 'unauthorized' }), {
      status: 401,
      headers: { 'Content-Type': 'application/json' },
    });
  }

  // ---- 2. Parse payload ----------------------------------------------------
  let payload: RcPayload;
  try {
    payload = await req.json();
  } catch {
    return new Response(JSON.stringify({ error: 'invalid_json' }), {
      status: 400,
      headers: { 'Content-Type': 'application/json' },
    });
  }

  const event = payload.event;
  if (!event || typeof event.type !== 'string') {
    return new Response(JSON.stringify({ ignored: 'missing_event_or_type' }), {
      status: 200,
      headers: { 'Content-Type': 'application/json' },
    });
  }

  const appUserId = event.app_user_id;
  // Anonymous users who never called Purchases.logIn are expected here —
  // acknowledge with 200 so RevenueCat stops retrying.
  if (
    !appUserId ||
    typeof appUserId !== 'string' ||
    appUserId.startsWith('$RCAnonymousID') ||
    appUserId.length > 128
  ) {
    console.log(JSON.stringify({
      function: 'revenuecat-webhook',
      stage: 'ignored_anonymous_app_user',
      eventType: event.type,
    }));
    return new Response(JSON.stringify({ ignored: 'anonymous_app_user' }), {
      status: 200,
      headers: { 'Content-Type': 'application/json' },
    });
  }

  const status = statusForEventType(event.type);
  if (!status) {
    console.log(JSON.stringify({
      function: 'revenuecat-webhook',
      stage: 'ignored_event_type',
      eventType: event.type,
    }));
    return new Response(JSON.stringify({ ignored: `unhandled_type_${event.type}` }), {
      status: 200,
      headers: { 'Content-Type': 'application/json' },
    });
  }

  // ---- 3. Upsert entitlement via service_role (bypasses RLS) ---------------
  const admin = createClient(SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY, {
    auth: { persistSession: false },
  });

  const row = {
    user_id: appUserId,
    product_id: event.product_id ?? null,
    entitlement_id: event.entitlement_ids?.[0] ?? null,
    status,
    expires_at:
      typeof event.expiration_at_ms === 'number'
        ? new Date(event.expiration_at_ms).toISOString()
        : null,
    store: event.store ?? null,
    updated_at: new Date().toISOString(),
  };

  const { error } = await admin.from('entitlements').upsert(row, { onConflict: 'user_id' });
  if (error) {
    // Return 500 so RevenueCat retries automatically until the write succeeds.
    console.error(JSON.stringify({
      level: 'ERROR',
      function: 'revenuecat-webhook',
      stage: 'db_upsert_failed',
      eventType: event.type,
      userId: appUserId,
      error: error.message,
      code: (error as { code?: string }).code,
    }));
    return new Response(JSON.stringify({ error: 'db_write_failed' }), {
      status: 500,
      headers: { 'Content-Type': 'application/json' },
    });
  }

  console.log(JSON.stringify({
    function: 'revenuecat-webhook',
    stage: 'entitlement_updated',
    eventType: event.type,
    userId: appUserId,
    status,
    expiresAt: row.expires_at,
  }));
  return new Response(JSON.stringify({ ok: true }), {
    status: 200,
    headers: { 'Content-Type': 'application/json' },
  });
});
