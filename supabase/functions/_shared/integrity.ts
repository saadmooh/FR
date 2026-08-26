// Shared Play Integrity verification used by ai-proxy and session-token.
//
// Extracted verbatim from ai-proxy so both edge functions reuse the exact
// same logic (Google access token, decodeIntegrityToken call, nonce check,
// freshness, package/cert pinning, device + licensing verdicts).
//
// Required secrets (set with `supabase secrets set`):
//   GOOGLE_SERVICE_ACCOUNT_JSON — service-account JSON for Play Integrity API
//   EXPECTED_PACKAGE_NAME       — optional, default com.saadmohammed2000.flex_reminder
//   EXPECTED_CERT_SHA256        — comma-separated SHA-256 signing cert digests

export const EXPECTED_PACKAGE_NAME =
  Deno.env.get('EXPECTED_PACKAGE_NAME') ?? 'com.saadmohammed2000.flex_reminder';

export const EXPECTED_CERT_HASHES = (Deno.env.get('EXPECTED_CERT_SHA256') ?? '')
  .split(',')
  .map((s) => s.trim())
  .filter(Boolean);

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

export async function sha256Base64(input: string): Promise<string> {
  const digest = await crypto.subtle.digest('SHA-256', encoder.encode(input));
  // Use the first 30 bytes (a multiple of 3) so the Base64 is a clean 40-char
  // string with no padding. Must match the client's generateNonce().
  const bytes = new Uint8Array(digest).slice(0, 30);
  let binary = '';
  for (let i = 0; i < bytes.length; i++) {
    binary += String.fromCharCode(bytes[i]);
  }
  // URL-safe Base64 — matches the client nonce exactly.
  return btoa(binary).replace(/\+/g, '-').replace(/\//g, '_').replace(/=+$/g, '');
}

export function base64ToBytes(input: string): Uint8Array {
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

export interface DiagnosticData {
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

export async function verifyIntegrityToken(
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
