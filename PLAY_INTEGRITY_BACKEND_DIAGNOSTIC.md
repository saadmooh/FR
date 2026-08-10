# Play Integrity Backend Diagnostic Implementation

## File Modified

**`supabase/functions/ai-proxy/index.ts`**

---

## Where `decodeIntegrityToken` Happens

**Function:** `verifyIntegrityToken()` (lines 194-330)

**API Call:**
```typescript
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
```

- **Endpoint:** `https://playintegrity.googleapis.com/v1/{packageName}:decodeIntegrityToken`
- **Auth:** Service Account JWT (OAuth2) with scope `https://www.googleapis.com/auth/playintegrity`
- **Input:** Base64-encoded integrity token from client
- **Output:** Decoded payload in `data.tokenPayloadExternal`

---

## All Checks Performed

### 1. **Decode Stage** (`stage: "decode_integrity_token"`)
- HTTP call to Google Play Integrity API
- Service Account authentication
- Response status check

### 2. **Request Details** (`stage: "backend_verification"`)
| Check | Field | Description |
|-------|-------|-------------|
| Present | `requestDetailsPresent` | `payload.requestDetails` exists |
| Present | `requestHashPresent` | `requestHash` exists in requestDetails |
| Match | `requestHashMatches` | `requestHash === SHA256(nonce)` |
| Present | `timestampPresent` | `timestampMillis` exists |
| Age | `tokenAgeSeconds` | Token age in seconds |

### 3. **App Integrity** (`stage: "backend_verification"`)
| Check | Field | Description |
|-------|-------|-------------|
| Present | `appIntegrityPresent` | `payload.appIntegrity` exists |
| Verdict | `appRecognitionVerdict` | `PLAY_RECOGNIZED` / `UNRECOGNIZED_VERSION` / `UNEVALUATED` / `MISSING` |
| Package | `packageName` | Package name from token |
| Match | `packageNameMatches` | `packageName === EXPECTED_PACKAGE_NAME` |
| Cert | `certificatePresent` | Certificate digest present (not exposed) |

### 4. **Device Integrity** (`stage: "backend_verification"`)
| Check | Field | Description |
|-------|-------|-------------|
| Present | `deviceIntegrityPresent` | `payload.deviceIntegrity` exists |
| Verdicts | `deviceRecognitionVerdict` | Array: `MEETS_DEVICE_INTEGRITY`, `MEETS_BASIC_INTEGRITY`, etc. |

### 5. **Licensing** (`stage: "backend_verification"`)
| Check | Field | Description |
|-------|-------|-------------|
| Present | `licensingPresent` | `payload.accountDetails` exists |
| Verdict | `licensingVerdict` | `LICENSED` / `UNLICENSED` / `UNEVALUATED` / `MISSING` |

---

## Diagnostic Response Format

### On Failure (HTTP 403):
```json
{
  "error": {
    "code": "INTEGRITY_FAILED",
    "message": "App integrity check failed, update the app to the latest version",
    "diagnostic": {
      "stage": "backend_verification",
      "decodeSuccess": true,
      "requestDetailsPresent": true,
      "requestHashPresent": true,
      "requestHashMatches": true,
      "timestampPresent": true,
      "tokenAgeSeconds": 12,
      "appIntegrityPresent": true,
      "appRecognitionVerdict": "UNRECOGNIZED_VERSION",
      "packageName": "com.saadmohammed2000.flex_reminder",
      "packageNameMatches": true,
      "certificatePresent": true,
      "deviceIntegrityPresent": true,
      "deviceRecognitionVerdict": ["MEETS_DEVICE_INTEGRITY"],
      "licensingVerdict": "LICENSED",
      "licensingPresent": true,
      "failedChecks": ["appRecognitionVerdict=UNRECOGNIZED_VERSION"]
    }
  }
}
```

### On Decode Failure:
```json
{
  "error": {
    "code": "INTEGRITY_FAILED",
    "message": "App integrity check failed, update the app to the latest version",
    "diagnostic": {
      "stage": "backend_decode_failed",
      "decodeSuccess": false,
      "errorType": "HTTP_ERROR",
      "errorMessage": "Integrity decode failed: 401",
      "failedChecks": ["decodeIntegrityTokenHTTPError"]
    }
  }
}
```

### Possible `failedChecks` Values:
| Value | Meaning |
|-------|---------|
| `decodeIntegrityTokenHTTPError` | Google API returned non-200 |
| `decodeException` | Exception during decode |
| `requestHashMissing` | No requestHash in token |
| `requestHashMismatch` | SHA256(nonce) ≠ requestHash |
| `timestampMissing` | No timestampMillis |
| `tokenExpired` | Token > 5 minutes old |
| `packageNameMismatch` | Package name doesn't match |
| `appRecognitionVerdict=UNRECOGNIZED_VERSION` | App not recognized (version mismatch) |
| `appRecognitionVerdict=UNEVALUATED` | Not from Play Store |
| `deviceIntegrityFailed` | Device doesn't meet integrity |

---

## How to Test from App

1. **Build & Upload** to Internal Testing:
   ```bash
   flutter build appbundle --dart-define=GCP_CLOUD_PROJECT_NUMBER=1038373651011 --dart-define=STRICT_INTEGRITY_CHECK=true ...
   ```

2. **Install from Play Store** on test device (Internal Testing track)

3. **Trigger Save Post** action in app

4. **Snackbar will show** diagnostic like:
   ```
   Google Play Integrity Diagnostic
   Stage: backend_verification
   Backend status: 403
   App recognition: UNRECOGNIZED_VERSION
   Package: com.saadmohammed2000.flex_reminder
   Package matches: true
   Request hash: MATCH
   Device integrity: MEETS_DEVICE_INTEGRITY
   Token age: 14 seconds
   Failed checks: appRecognitionVerdict=UNRECOGNIZED_VERSION
   Code: INTEGRITY_FAILED
   Message: App integrity check failed, update the app to the latest version
   ```

5. **Copy/screenshot** and send for analysis

---

## Security Confirmation

✅ **Integrity NOT disabled** - `ALLOW_DEBUG_BYPASS` only works if explicitly set in Supabase secrets  
✅ **No token logging** - `integrityToken` never logged or returned  
✅ **No secrets exposed** - Service Account JSON, JWTs, API keys never in response  
✅ **No certificate digest exposed** - Only `certificatePresent: true/false`  
✅ **403 maintained** - All failures return HTTP 403 with `INTEGRITY_FAILED`  
✅ **No database changes** - No migrations, no storage  

---

## No Automatic Deploy

This file must be deployed manually via:
```bash
supabase functions deploy ai-proxy --project-ref <project-ref>
```
Or through Supabase Dashboard.
