# Actual Error Trace Report

## Exact Error Message Source

**File:** `supabase/functions/ai-proxy/index.ts`  
**Line:** 453  
**Code:**
```typescript
return jsonError(
  403,
  'INTEGRITY_FAILED',
  'App integrity check failed, update the app to the latest version',
  diagnostic,
);
```

**Flutter Client - Arabic Message Creation:** `lib/services/ai_proxy_service.dart` lines 213, 220
```dart
case 'INTEGRITY_FAILED':
  return AiProxyException(
    403,
    code,
    'فشل التحقق من التطبيق ($code): $message',  // Arabic wrapper
    diagnostic: diagnostic,
  );
```

**Flutter UI - Display:** `lib/widgets/save_post_sheet.dart` line 317
```dart
errorMessage = '${Translations.errorSavingPost(_locale)}: [Google Play Integrity] ${e.message} (Code: ${e.code}, Status: ${e.statusCode})';
```

---

## Complete Call Flow

```
UI (save_post_sheet.dart:_save())
    ↓
AIService.classifyContent() / estimateBestTime()
    ↓
AiProxyService.sendPrompt()
    ↓
IntegrityService.generateNonce() → nonce generated
    ↓
IntegrityService.requestIntegrityToken()
    ↓
FlutterPlayIntegrityWrapper.requestIntegrityToken()  [NATIVE/Kotlin]
    ↓
Google Play Services → Integrity Token
    ↓ (if token received)
AiProxyService.sendPrompt() continues
    ↓
Supabase Edge Function (ai-proxy) invoked via client.functions.invoke()
    ↓
Backend: getGoogleAccessToken() (Service Account)
    ↓
Backend: POST https://playintegrity.googleapis.com/v1/{pkg}:decodeIntegrityToken
    ↓
Backend: verifyIntegrityToken() - all checks
    ↓
Backend: Returns 403 with diagnostic
    ↓
Flutter: FunctionException caught in _mapHttpException()
    ↓
AiProxyException thrown with diagnostic
    ↓
save_post_sheet.dart catch block catches AiProxyException
    ↓ [NEW] INTEGRITY TRACE SnackBar shown
    ↓ Original error SnackBar shown
```

---

## Actual Exception Type

**Primary:** `AiProxyException` (from `lib/services/ai_proxy_service.dart`)

**Wrapping:** The original error comes from Supabase Edge Function as HTTP 403 with body:
```json
{
  "error": {
    "code": "INTEGRITY_FAILED",
    "message": "App integrity check failed, update the app to the latest version"
  },
  "diagnostic": { ... }
}
```

**Exception Chain:**
1. `FunctionException` (from `client.functions.invoke()`)
2. Caught in `ai_proxy_service.dart` line 145 → `_mapHttpException()`
3. Creates `AiProxyException` with statusCode=403, code='INTEGRITY_FAILED'
4. Thrown to `save_post_sheet.dart` line 286 catch block

---

## Actual Error Code

**Backend Code:** `INTEGRITY_FAILED` (from `supabase/functions/ai-proxy/index.ts`)

**Flutter Code:** `INTEGRITY_FAILED` (propagated through `AiProxyException.code`)

**HTTP Status:** 403

---

## HTTP Status

**403** - Returned by Supabase Edge Function when `verifyIntegrityToken()` returns `passed: false`

---

## Backend Request

**SENT** - The request to Supabase Edge Function IS being sent (since we get HTTP 403 response)

**Evidence:** 
- `client.functions.invoke('ai-proxy', ...)` executes
- Returns `FunctionException` with status 403
- Backend diagnostic is included in response

---

## Integrity Token

**REQUESTED:** YES - `IntegrityService.requestIntegrityToken()` is called

**RECEIVED:** YES (likely) - Since backend request was sent with `X-Integrity-Token` header

**Evidence from diagnostic:**
- If `diagnostic.tokenReceived == true` → token obtained from Play Services
- If `diagnostic.stage == 'token_received'` → token received successfully
- If `diagnostic.stage == 'token_request_failed'` → token NOT received (client-side failure)

---

## Integrity Token Received

**Status:** Determined by diagnostic

- **If `diagnostic.tokenReceived == true`** → YES, token obtained from Google Play Services
- **If `diagnostic.stage == 'token_request_failed'`** → NO, PlayIntegrityException thrown
- **If `diagnostic.stage == 'unexpected_error'`** → NO, unexpected error

---

## Files Modified for Trace

| File | Purpose |
|------|---------|
| `lib/widgets/save_post_sheet.dart` | Added comprehensive INTEGRITY TRACE at catch block (line ~286) |
| `lib/core/integrity_snackbar.dart` | Created (utility for formatted SnackBars) |
| `lib/main.dart` | Added `scaffoldMessengerKey` global key |
| `lib/models/integrity_diagnostic.dart` | Existing diagnostic model |
| `lib/services/integrity_service.dart` | Existing diagnostic logging at each stage |
| `lib/services/ai_proxy_service.dart` | Existing diagnostic propagation |
| `lib/services/ai_service.dart` | Existing diagnostic exposure |

---

## SnackBar Diagnostic Location

**Where:** `lib/widgets/save_post_sheet.dart` in the `_save()` method catch block (after line 286)

**When:** Immediately when any exception is caught during the save operation

**What it shows:**
```
━━━━━━━━━━━━━━━━━━━━
INTEGRITY TRACE
━━━━━━━━━━━━━━━━━━━━

Exception type: AiProxyException
Source: BACKEND / CLIENT / BACKEND_CONNECTION
Code: INTEGRITY_FAILED
HTTP status: 403
Message: App integrity check failed, update the app to the latest version

Integrity token requested: YES
Integrity token received: YES/NO
Backend request started: YES
Backend response received: YES

--- Diagnostic ---
Stage: backend_verification
Token received: YES
Token length: 1248
Backend status: 403
App recognition: UNRECOGNIZED_VERSION
Package: com.saadmohammed2000.flex_reminder
Package matches: YES
Request hash: MATCH
Device integrity: MEETS_DEVICE_INTEGRITY
Token age: 12s
Failed checks: appRecognitionVerdict=UNRECOGNIZED_VERSION

━━━━━━━━━━━━━━━━━━━━
```

**Duration:** 15 seconds  
**Style:** Monospace, selectable text, red background for errors

---

## Key Trace Markers Added

| Marker | Location | Purpose |
|--------|----------|---------|
| `INTEGRITY_TRACE_POINT_002` | `save_post_sheet.dart` catch block | Final exception caught in UI |
| `debugPrint('INTEGRITY_TRACE: ...')` | Same location | Console log for debugging |

---

## Expected Diagnostic Outcomes

### If Source = CLIENT
- `tokenReceived: NO`
- `backendRequestSent: NO`
- `backendResponseReceived: NO`
- `diagnostic.stage: token_request_failed`
- `diagnostic.code: INTEGRITY_ERROR_APP_UID_MISMATCH` or similar PlayIntegrity error

### If Source = BACKEND (current case)
- `tokenReceived: YES`
- `backendRequestSent: YES`
- `backendResponseReceived: YES`
- `diagnostic.stage: backend_verification`
- `diagnostic.appRecognitionVerdict: UNRECOGNIZED_VERSION`
- `diagnostic.failedChecks: ["appRecognitionVerdict=UNRECOGNIZED_VERSION"]`

### If Source = BACKEND_CONNECTION
- `tokenReceived: YES`
- `backendRequestSent: YES`
- `backendResponseReceived: NO`
- Error: NETWORK_ERROR or TIMEOUT

---

## No Changes To

- ✅ Google Play configuration
- ✅ Package name / versionCode / versionName
- ✅ Signing keys
- ✅ cloudProjectNumber
- ✅ Supabase Edge Function (not modified in this trace)
- ✅ Play Integrity implementation
- ✅ flutter_play_integrity_wrapper
