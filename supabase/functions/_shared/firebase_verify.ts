// Verifies Firebase Auth ID tokens (RS256) against Google's public JWK set.
//
// Checks: signature, issuer, audience (= FIREBASE_PROJECT_ID), expiry and a
// non-empty `sub` (the Firebase UID). The JWK set is cached in memory using
// Google's Cache-Control max-age.

interface FirebaseJwk {
  kty: string;
  alg: string;
  kid: string;
  n: string;
  e: string;
}

const JWKS_URL =
  'https://www.googleapis.com/service_accounts/v1/jwk/securetoken@system.gserviceaccount.com';

let jwksCache: { keys: Map<string, CryptoKey>; expiresAt: number } | null = null;

const decoder = new TextDecoder();

function base64UrlToBytes(input: string): Uint8Array {
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

async function loadJwks(): Promise<Map<string, CryptoKey>> {
  const now = Date.now();
  if (jwksCache && now < jwksCache.expiresAt) {
    return jwksCache.keys;
  }

  const res = await fetch(JWKS_URL, { cache: 'no-store' });
  if (!res.ok) {
    throw new Error(`Failed to fetch Firebase JWKS: ${res.status}`);
  }
  const data = await res.json();
  const keys = new Map<string, CryptoKey>();
  for (const jwk of data.keys as FirebaseJwk[]) {
    if (jwk.alg !== 'RS256' || jwk.kty !== 'RSA') continue;
    const cryptoKey = await crypto.subtle.importKey(
      'jwk',
      jwk as unknown as JsonWebKey,
      { name: 'RSASSA-PKCS1-v1_5', hash: 'SHA-256' },
      false,
      ['verify'],
    );
    keys.set(jwk.kid, cryptoKey);
  }

  // Refresh at half the advertised max-age (fallback: 1 hour).
  const maxAgeSeconds = Number(res.headers.get('cache-control')?.match(/max-age=(\d+)/)?.[1] ?? 3600);
  jwksCache = { keys, expiresAt: now + Math.max(60, Math.floor(maxAgeSeconds / 2)) * 1000 };
  return keys;
}

export interface FirebaseAuthContext {
  uid: string;
}

/**
 * Verifies a Firebase ID token from an `Authorization: Bearer <jwt>` header.
 * Returns the caller's Firebase UID or null (with console logging).
 * Requires the FIREBASE_PROJECT_ID secret.
 */
export async function verifyFirebaseIdToken(
  authHeader: string | null,
): Promise<FirebaseAuthContext | null> {
  const projectId = Deno.env.get('FIREBASE_PROJECT_ID');
  if (!projectId) {
    console.error(JSON.stringify({
      level: 'ERROR',
      error: 'FIREBASE_PROJECT_ID secret is not configured',
    }));
    return null;
  }

  const token = authHeader?.startsWith('Bearer ') ? authHeader.slice(7).trim() : '';
  if (!token) return null;

  const parts = token.split('.');
  if (parts.length !== 3) return null;

  let headerKid: string | undefined;
  try {
    headerKid = JSON.parse(decoder.decode(base64UrlToBytes(parts[0])))?.kid;
  } catch {
    return null;
  }
  if (!headerKid) return null;

  let payload: Record<string, unknown>;
  try {
    payload = JSON.parse(decoder.decode(base64UrlToBytes(parts[1])));
  } catch {
    return null;
  }

  const keys = await loadJwks();
  const key = keys.get(headerKid);
  if (!key) return null;

  const signatureBytes = base64UrlToBytes(parts[2]);
  const valid = await crypto.subtle.verify(
    'RSASSA-PKCS1-v1_5',
    key,
    signatureBytes,
    new TextEncoder().encode(`${parts[0]}.${parts[1]}`),
  );
  if (!valid) return null;

  const now = Math.floor(Date.now() / 1000);
  if (payload.iss !== `https://securetoken.google.com/${projectId}`) return null;
  if (payload.aud !== projectId) return null;
  if (typeof payload.exp !== 'number' || payload.exp <= now) return null;
  if (typeof payload.iat === 'number' && payload.iat > now + 300) return null;

  const uid = payload.sub;
  if (typeof uid !== 'string' || uid.length === 0 || uid.length > 128) return null;

  return { uid };
}
