# Play Integrity Debug Implementation

## Changes Made

### 1. New Files Created
- **`lib/models/integrity_diagnostic.dart`** - Diagnostic data model with structured fields for all integrity verification stages

### 2. Modified Files
- **`lib/services/integrity_service.dart`** - Added diagnostic logging at each stage of token request
- **`lib/services/ai_proxy_service.dart`** - Added diagnostic propagation through the call chain, added `X-Debug-Integrity` header
- **`lib/models/ai_proxy_response.dart`** - Added `diagnostic` field to `AiProxyException`
- **`lib/services/ai_service.dart`** - Added diagnostic property exposure to UI
- **`lib/widgets/save_post_sheet.dart`** - Added diagnostic display in error snackbar
- **`supabase/functions/ai-proxy/index.ts`** - Added comprehensive diagnostic return in error responses

---

## Client Diagnostic Flow

### Stage 1: Request Start (`lib/services/integrity_service.dart`)
```dart
INTEGRITY_DIAGNOSTIC:
stage=request_start
cloudProjectNumber=1038373651011
enabled=true
```

### Stage 2: Token Request
```dart
INTEGRITY_DIAGNOSTIC:
stage=token_request
nonce_length=44
```

### Stage 3: Token Received (Success)
```dart
INTEGRITY_DIAGNOSTIC:
stage=token_received
token_received=true
token_length=1248
```

### Stage 4: Token Request Failed (PlayIntegrityException)
```dart
INTEGRITY_DIAGNOSTIC:
stage=token_request_failed
code=INTEGRITY_ERROR_APP_UID_MISMATCH
message=App UID mismatch.
details=null
```

### Stage 5: Unexpected Error
```dart
INTEGRITY_DIAGNOSTIC:
stage=unexpected_error
code=UNKNOWN
message=...
errorType=SomeException
```

---

## Backend Diagnostic Flow

### Successful Token Decode
```json
{
  "stage": "backend_verification",
  "decodeSuccess": true,
  "requestDetailsPresent": true,
  "requestHashPresent": true,
  "requestHashMatches": true,
  "tokenAgeSeconds": 14,
  "appIntegrityPresent": true,
  "appRecognitionVerdict": "PLAY_RECOGNIZED",
  "packageName": "com.saadmohammed2000.flex_reminder",
  "packageNameMatches": true,
  "certificatePresent": true,
  "deviceIntegrityPresent": true,
  "deviceRecognitionVerdict": ["MEETS_DEVICE_INTEGRITY"],
  "licensingVerdict": "LICENSED",
  "licensingPresent": true
}
```

### Decode Failed (HTTP Error)
```json
{
  "stage": "backend_decode_failed",
  "decodeSuccess": false,
  "errorType": "HTTP_ERROR",
  "errorMessage": "Integrity decode failed: 401"
}
```

### Verification Failed (Verdict Mismatch)
```json
{
  "stage": "backend_verification",
  "decodeSuccess": true,
  "requestDetailsPresent": true,
  "requestHashPresent": true,
  "requestHashMatches": true,
  "tokenAgeSeconds": 14,
  "appIntegrityPresent": true,
  "appRecognitionVerdict": "UNRECOGNIZED_VERSION",
  "packageName": "com.saadmohammed2000.flex_reminder",
  "packageNameMatches": true,
  "certificatePresent": true,
  "deviceIntegrityPresent": true,
  "deviceRecognitionVerdict": ["MEETS_DEVICE_INTEGRITY"],
  "licensingVerdict": "LICENSED",
  "licensingPresent": true
}
```

---

## Security

✅ **No Integrity Token stored** - Tokens are only held in memory during request lifecycle  
✅ **No Token logging** - Diagnostic logs never include the actual token value  
✅ **No Secrets exposed** - Service Account JSON, API keys, JWTs, Authorization headers never logged  
✅ **No Integrity bypass** - `X-Debug-Integrity` header only adds diagnostic info, does NOT bypass verification  
✅ **403 still returned on failure** - Diagnostic data is included in error response, but HTTP 403 is maintained  
✅ **No database storage** - No Supabase tables, migrations, or columns added  
✅ **Nonce never fully exposed** - Only length is logged/displayed  

---

## Expected Diagnostic Cases

| Stage | Meaning | Action |
|-------|---------|--------|
| `request_start` | IntegrityService initialized | Check cloudProjectNumber, enabled |
| `token_request` | Calling Play Integrity API | Verify nonce length (should be 44) |
| `token_received` | Token successfully obtained | Check token_length (typically 1000+) |
| `token_request_failed` | **Client-side failure** | Check `code`: `INTEGRITY_ERROR_APP_UID_MISMATCH` = signature mismatch; `INTEGRITY_ERROR_CLOUD_PROJECT_NUMBER_IS_INVALID` = wrong project number; `INTEGRITY_ERROR_API_NOT_AVAILABLE` = Play Services too old |
| `unexpected_error` | Unexpected exception | Check errorType, message |
| `backend_decode_failed` | **Backend decode failure** | Google API returned error (401/403/500) - check service account permissions |
| `backend_verification` | **Token decoded but verdict failed** | Check `appRecognitionVerdict`: `UNRECOGNIZED_VERSION` = version mismatch; `UNEVALUATED` = not from Play Store; Check `requestHashMatches`: false = nonce mismatch; Check `deviceRecognitionVerdict`: missing `MEETS_DEVICE_INTEGRITY` = rooted/emulator |

---

## Testing Instructions

### For You (On Test Device):

1. **Install latest Internal Testing release from Google Play**
   - Open Play Store → Internal Testing → Install/Update
   - Wait for download to complete

2. **Open the app and sign in** (if required)

3. **Trigger the action that causes the error**
   - Try to save a post/URL (the Save Post flow)
   - This triggers the AI Proxy → Play Integrity verification

4. **Copy the diagnostic message that appears**
   - A snackbar will show with "Google Play Integrity Diagnostic"
   - It will include all available diagnostic fields
   - **Long-press the snackbar text to copy** (or screenshot)

5. **Send the diagnostic output to ChatGPT**

### Example Diagnostic Output You'll See:

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
Code: INTEGRITY_FAILED
Message: App integrity check failed, update the app to the latest version
```

---

## Files Modified Summary

| File | Type | Purpose |
|------|------|---------|
| `lib/models/integrity_diagnostic.dart` | NEW | Diagnostic data model |
| `lib/services/integrity_service.dart` | MODIFIED | Client-side diagnostic logging |
| `lib/services/ai_proxy_service.dart` | MODIFIED | Diagnostic propagation + debug header |
| `lib/models/ai_proxy_response.dart` | MODIFIED | Exception diagnostic field |
| `lib/services/ai_service.dart` | MODIFIED | Expose diagnostic to UI |
| `lib/widgets/save_post_sheet.dart` | MODIFIED | Display diagnostic in snackbar |
| `supabase/functions/ai-proxy/index.ts` | MODIFIED | Backend diagnostic in error responses |

---

## Next Steps

After you provide the diagnostic output from the device, we can determine:

1. **If `stage=token_request_failed` with `INTEGRITY_ERROR_APP_UID_MISMATCH`** → Signature mismatch (local vs Play signing)
2. **If `stage=backend_verification` with `appRecognitionVerdict=UNRECOGNIZED_VERSION`** → Version code mismatch
3. **If `stage=backend_decode_failed`** → Service account / Google Cloud config issue
4. **If `requestHashMatches=false`** → Nonce generation/transmission issue
5. **If `deviceRecognitionVerdict` missing `MEETS_DEVICE_INTEGRITY`** → Device/emulator issue

---

## Warning

**Do NOT:**
- Deploy this to production without removing diagnostic display
- Store diagnostic data in databases
- Log full tokens or secrets
- Use `X-Debug-Integrity` as a bypass mechanism

This implementation is for **diagnosis only** and maintains full security enforcement.
