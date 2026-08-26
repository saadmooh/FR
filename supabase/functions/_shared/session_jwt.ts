// Short-lived session JWTs (HS256) issued by the session-token edge function
// and verified by ai-proxy. The signing secret (SESSION_TOKEN_SECRET) is fully
// separate from REVENUECAT_WEBHOOK_SECRET and SUPABASE_SERVICE_ROLE_KEY.

export interface SessionClaims {
  uid: string;
  entitlement: string;
  iat: number;
  exp: number;
}

const encoder = new TextEncoder();
const decoder = new TextDecoder();

function base64UrlEncode(input: Uint8Array | string): string {
  const bytes = typeof input === 'string' ? encoder.encode(input) : input;
  let binary = '';
  for (let i = 0; i < bytes.length; i++) {
    binary += String.fromCharCode(bytes[i]);
  }
  return btoa(binary).replace(/\+/g, '-').replace(/\//g, '_').replace(/=+$/g, '');
}

function base64UrlDecode(input: string): Uint8Array {
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

async function hmacKey(secret: string): Promise<CryptoKey> {
  return crypto.subtle.importKey(
    'raw',
    encoder.encode(secret),
    { name: 'HMAC', hash: 'SHA-256' },
    false,
    ['sign', 'verify'],
  );
}

/** Signs { uid, entitlement: 'pro', iat, exp } as a compact HS256 JWT. */
export async function signSessionToken(
  uid: string,
  secret: string,
  ttlSeconds: number,
): Promise<{ token: string; expiresIn: number }> {
  const now = Math.floor(Date.now() / 1000);
  const header = base64UrlEncode(JSON.stringify({ alg: 'HS256', typ: 'JWT' }));
  const payload = base64UrlEncode(
    JSON.stringify({ uid, entitlement: 'pro', iat: now, exp: now + ttlSeconds }),
  );
  const key = await hmacKey(secret);
  const signature = await crypto.subtle.sign(
    'HMAC',
    key,
    encoder.encode(`${header}.${payload}`),
  );
  return {
    token: `${header}.${payload}.${base64UrlEncode(new Uint8Array(signature))}`,
    expiresIn: ttlSeconds,
  };
}

/**
 * Verifies signature + exp + required claims. Returns the claims on success.
 * Never throws — callers branch on `valid`.
 */
export async function verifySessionToken(
  token: string,
  secret: string,
): Promise<{ valid: boolean; reason?: string; claims?: SessionClaims }> {
  if (!token || !secret) {
    return { valid: false, reason: !secret ? 'server_not_configured' : 'token_missing' };
  }

  const parts = token.split('.');
  if (parts.length !== 3 || !parts[0] || !parts[1] || !parts[2]) {
    return { valid: false, reason: 'malformed' };
  }

  let headerAlg: string | undefined;
  try {
    headerAlg = JSON.parse(decoder.decode(base64UrlDecode(parts[0])))?.alg;
  } catch {
    return { valid: false, reason: 'malformed_header' };
  }
  if (headerAlg !== 'HS256') {
    return { valid: false, reason: 'bad_algorithm' };
  }

  let claims: SessionClaims;
  try {
    claims = JSON.parse(decoder.decode(base64UrlDecode(parts[1])));
  } catch {
    return { valid: false, reason: 'malformed_payload' };
  }

  const key = await hmacKey(secret);
  const expectedSig = await crypto.subtle.sign(
    'HMAC',
    key,
    encoder.encode(`${parts[0]}.${parts[1]}`),
  );
  const providedSig = base64UrlDecode(parts[2]);
  const actualSig = new Uint8Array(expectedSig);

  // Constant-time comparison.
  if (
    providedSig.length !== actualSig.length ||
    !actualSig.every((b, i) => b === providedSig[i])
  ) {
    return { valid: false, reason: 'bad_signature' };
  }

  const now = Math.floor(Date.now() / 1000);
  if (typeof claims.exp !== 'number' || claims.exp <= now - 30) {
    return { valid: false, reason: 'expired' };
  }
  if (typeof claims.uid !== 'string' || claims.uid.length === 0) {
    return { valid: false, reason: 'missing_uid' };
  }
  if (claims.entitlement !== 'pro') {
    return { valid: false, reason: 'not_entitled' };
  }

  return { valid: true, claims };
}
