# Supabase Edge Function Headers

## Headers Sent to `ai-proxy` Edge Function

### Always Sent (Both Test & Production)

| Header | Value | Description |
|--------|-------|-------------|
| `X-Integrity-Token` | Base64 Play Integrity token | Token obtained from Google Play Services via `flutter_play_integrity_wrapper` |
| `X-Request-Nonce` | Base64 URL-safe (no padding) | SHA-256 hash of prompt + random salt, used for replay protection |
| `X-Debug-Integrity` | `"true"` | Added for diagnostics |

---

### Production Only (`STRICT_INTEGRITY_CHECK=true`)

| Header | Value | Description |
|--------|-------|-------------|
| `X-Debug-Build` | **NOT SENT** | Debug bypass disabled |

### Test/Debug Only (`STRICT_INTEGRITY_CHECK=false`)

| Header | Value | Description |
|--------|-------|-------------|
| `X-Debug-Build` | `"true"` | Enables backend debug bypass |

---

## Configuration Control

### Build-Time Configuration (`lib/core/app_config.dart`)

```dart
static const bool strictIntegrityCheck =
    bool.fromEnvironment('STRICT_INTEGRITY_CHECK', defaultValue: true);
```

### Build Commands

```bash
# PRODUCTION - Strict check ON, no debug bypass
flutter build appbundle \
  --dart-define=STRICT_INTEGRITY_CHECK=true \
  --dart-define=GCP_CLOUD_PROJECT_NUMBER=1038373651011 \
  --dart-define=SUPABASE_URL=... \
  --dart-define=SUPABASE_ANON_KEY=...

# TEST/DEBUG - Strict check OFF, allows debug builds
flutter build appbundle \
  --dart-define=STRICT_INTEGRITY_CHECK=false \
  --dart-define=GCP_CLOUD_PROJECT_NUMBER=1038373651011 \
  --dart-define=SUPABASE_URL=... \
  --dart-define=SUPABASE_ANON_KEY=...
```

---

## Backend Verification Logic (`supabase/functions/ai-proxy/index.ts`)

```typescript
const isDebugBuild = req.headers.get('X-Debug-Build') === 'true';

if (ALLOW_DEBUG_BYPASS && isDebugBuild) {
  console.log('Debug build detected, skipping integrity check');
  // SKIPS all Play Integrity verification
} else {
  // FULL verification:
  // 1. decodeIntegrityToken via Google Play Integrity API
  // 2. requestHash matches SHA-256(nonce)
  // 3. tokenAge < 5 minutes
  // 4. appRecognitionVerdict === 'PLAY_RECOGNIZED'
  // 5. packageName matches expected
  // 6. deviceRecognitionVerdict includes 'MEETS_DEVICE_INTEGRITY'
}
```

---

## Requirements for Debug Bypass

1. **Client**: Build with `--dart-define=STRICT_INTEGRITY_CHECK=false`
2. **Backend**: Set Supabase secret `ALLOW_DEBUG_BYPASS=true`
3. **Result**: `X-Debug-Build: true` header sent → backend skips all integrity checks

---

## Example Request Headers

### Production Request
```
POST /functions/v1/ai-proxy
Authorization: Bearer <supabase_jwt>
Content-Type: application/json
X-Integrity-Token: <base64_token_from_google_play>
X-Request-Nonce: <base64_sha256_prompt_salt>
X-Debug-Integrity: true
```

### Debug/Test Request
```
POST /functions/v1/ai-proxy
Authorization: Bearer <supabase_jwt>
Content-Type: application/json
X-Integrity-Token: <base64_token_from_google_play>
X-Request-Nonce: <base64_sha256_prompt_salt>
X-Debug-Integrity: true
X-Debug-Build: true
```

---

## Related Files

| File | Purpose |
|------|---------|
| `lib/services/ai_proxy_service.dart` | Header construction (lines 113-123) |
| `lib/core/app_config.dart` | `strictIntegrityCheck` configuration |
| `supabase/functions/ai-proxy/index.ts` | Backend verification logic |
| `lib/services/integrity_service.dart` | Token request to Play Services |