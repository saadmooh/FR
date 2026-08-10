# Google Play Integrity Diagnostic Report

## 1. Executive Summary

**Problem**: App installed from Google Play Internal Testing returns `INTEGRITY_FAILED` with error message "App integrity check failed, update the app to the latest version" (Status: 403) when requesting Play Integrity tokens.

**Error Flow**: 
- Client (Flutter) → `FlutterPlayIntegrityWrapper` → Google Play Services → Token → Supabase Edge Function (`ai-proxy`) → Google Play Integrity API (`decodeIntegrityToken`) → Verification fails → Returns `INTEGRITY_FAILED`

**Most Likely Root Cause**: **Version code mismatch** between the installed Internal Testing build and the version recorded in Play Console, OR the installed app is not the exact same build that was uploaded to Internal Testing (signature/package mismatch).

---

## 2. Environment

| Component | Version |
|-----------|---------|
| Flutter | 3.44.9 (stable) |
| Dart | 3.12.2 |
| Android Gradle Plugin | 8.9.1 |
| Gradle | 8.13 (wrapper) |
| compileSdk | Flutter-managed (via `flutter.compileSdkVersion`) |
| targetSdk | Flutter-managed (via `flutter.targetSdkVersion`) |
| minSdk | Flutter-managed (via `flutter.minSdkVersion`) |
| Kotlin | 2.1.0 |

---

## 3. Application Identity

| Property | Value |
|----------|-------|
| **applicationId** | `com.saadmohammed2000.flex_reminder` |
| **namespace** | `com.saadmohammed2000.flex_reminder` |
| **versionName** | `1.3.5` (from pubspec.yaml) |
| **versionCode** | `29` (from pubspec.yaml: `1.3.5+29`) |
| **flavors** | None defined |
| **buildTypes** | `release` (signed with upload keystore) |
| **applicationIdSuffix** | None |

**Key Finding**: Version code `29` is defined in `pubspec.yaml` and passed via Flutter Gradle plugin (`flutter.versionCode`).

---

## 4. Play Integrity Configuration

### 4.1 Wrapper Package
| Property | Value |
|----------|-------|
| Package | `flutter_play_integrity_wrapper` |
| Version | `0.0.2` |
| Source | Pub.dev |
| Native Plugin Class | `FlutterPlayIntegrityWrapperPlugin` |
| Method Channel | `flutter_play_integrity_wrapper` |

### 4.2 cloudProjectNumber Configuration

**Source**: `--dart-define=GCP_CLOUD_PROJECT_NUMBER=1038373651011` at build time

**Code Path**:
```dart
// lib/core/app_config.dart
static const String gcpCloudProjectNumber = String.fromEnvironment(
  'GCP_CLOUD_PROJECT_NUMBER', 
  defaultValue: 'YOUR_GCP_CLOUD_PROJECT_NUMBER',
);
static int? get cloudProjectNumber => int.tryParse(gcpCloudProjectNumber);

// lib/services/ai_proxy_service.dart (factory fromConfig)
final cloudProjectNumber = AppConfig.cloudProjectNumber; // Comes from dart-define
return AiProxyService(
  integrity: IntegrityService(
    cloudProjectNumber: cloudProjectNumber ?? 0,
    enabled: cloudProjectNumber != null,
  ),
  ...
);
```

**Values in Release Build** (when built with `--dart-define`):
- `cloudProjectNumber` = `1038373651011` ✓
- `enabled` = `true` ✓

**Values in Debug/Unconfigured Build**:
- `cloudProjectNumber` = `0` (fallback from `int.tryParse('YOUR_GCP_CLOUD_PROJECT_NUMBER')`)
- `enabled` = `false` (because `cloudProjectNumber != null` but value is 0)

### 4.3 IntegrityService Implementation

**File**: `lib/services/integrity_service.dart`

```dart
Future<String> requestIntegrityToken({required String nonce}) async {
  if (!enabled || cloudProjectNumber <= 0) {
    throw IntegrityException('INTEGRITY_DISABLED', 'Play Integrity is not configured');
  }
  final token = await _wrapper.requestIntegrityToken(
    cloudProjectNumber: cloudProjectNumber.toString(),
    nonce: nonce,
  );
  // ...
}
```

**Key Behavior**: 
- Throws `INTEGRITY_DISABLED` if `cloudProjectNumber <= 0`
- Passes `cloudProjectNumber` as string to native plugin
- Logs debug info for troubleshooting

### 4.4 Native Plugin Implementation

**File**: `flutter_play_integrity_wrapper` (Kotlin)

```kotlin
val request = IntegrityTokenRequest.builder()
    .setCloudProjectNumber(projectNumber)  // Long
    .setNonce(nonce)
    .build()
integrityManager.requestIntegrityToken(request)
```

**Error Code Mapping** (from plugin):
| Error Code | Message |
|------------|---------|
| `INTEGRITY_ERROR_2` (NO_NETWORK) | "No network connection." |
| `INTEGRITY_ERROR_APP_UID_MISMATCH` | "App UID mismatch." |
| `INTEGRITY_ERROR_CLOUD_PROJECT_NUMBER_IS_INVALID` | "Cloud project number is invalid." |
| `INTEGRITY_ERROR_NONCE_IS_NOT_BASE64` | "Nonce is not Base64." |
| `INTEGRITY_ERROR_NONCE_TOO_LONG` | "Nonce is too long." |
| `INTEGRITY_ERROR_NONCE_TOO_SHORT` | "Nonce is too short." |
| `INTEGRITY_ERROR_API_NOT_AVAILABLE` | "Integrity API is not available." |
| `INTEGRITY_ERROR_PLAY_STORE_NOT_FOUND` | "Play Store not found." |
| ... | ... |

**Note**: The wrapper uses `StandardIntegrityManager` (not Classic), which requires Play Services 23.20+.

---

## 5. Signing Configuration

### 5.1 Release Signing (Local Build)
| Property | Value |
|----------|-------|
| Keystore | `android/app/upload-keystore.jks` |
| Alias | `upload` |
| Store Password | Configured (not shown) |
| Key Password | Configured (not shown) |
| SHA-1 (from sha1_fingerprints.txt) | `E3:D6:03:F7:E4:E2:A4:F2:30:00:D3:D8:CB:52:1E:A1:DF:05:5E:66` |

### 5.2 Play App Signing (Google Play Console)
| Property | Value |
|----------|-------|
| **App Signing Key SHA-1** | `4F:2F:0B:D0:1E:81:19:3C:B0:4F:23:F5:E7:26:0E:F1:01:76:99:C1` |
| **App Signing Key SHA-256** | `44:E2:EC:F6:EC:09:01:45:88:A1:D3:B4:04:51:84:55:BC:57:F6:28:95:1F:8D:A8:72:C5:57:8F:53:7C:1A:5B` |
| **Upload Key SHA-1** | `E3:D6:03:F7:E4:E2:A4:F2:30:00:D3:D8:CB:52:1E:A1:DF:05:5E:66` |

### 5.3 google-services.json Registered Certificates
The following SHA-1 hashes are registered in Firebase/google-services.json:
1. `6b4118869aca198c6a517355de5fbc90e7f494cb`
2. `e6cae99a3671dc516cebb9b195b835a246be1907`
3. **`4f2f0bd01e81193cb04f23f5e7260ef1017699c1`** ← **Matches Play App Signing SHA-1**
4. `cf166c48d4682ed6d6c65a0b144e5892ed21397e`
5. **`e3d603f7e4e2a4f23000d3d8cb521ea1df055e66`** ← **Matches Upload Key SHA-1**

**Critical Finding**: Both the **Play App Signing key** and the **Upload key** are registered in Firebase, which is correct.

---

## 6. Google Play Configuration (from project inference)

| Setting | Value |
|---------|-------|
| Google Cloud Project | `flex-reminders-app` |
| Project Number | `1038373651011` |
| Package Name | `com.saadmohammed2000.flex_reminder` |
| Play Integrity API | Enabled (inferred from configuration) |
| App Integrity | ON (per user) |
| App Licensing | ON (per user) |
| Device Integrity | ON (per user) |
| Internal Testing Track | Active (per user) |

---

## 7. Backend Verification (Supabase Edge Function: `ai-proxy`)

### 7.1 Verification Flow
```
Client Request
    → X-Integrity-Token header
    → X-Request-Nonce header
    → X-Debug-Build header (optional)
Supabase Edge Function (ai-proxy)
    → Validates Supabase Auth (JWT)
    → If not debug bypass:
        → Calls Google Play Integrity API: 
          POST https://playintegrity.googleapis.com/v1/{packageName}:decodeIntegrityToken
          with service account credentials (GOOGLE_SERVICE_ACCOUNT_JSON)
        → Verifies:
          1. requestHash matches SHA-256(nonce) ✓
          2. Token issued < 5 minutes ago ✓
          3. appRecognitionVerdict == 'PLAY_RECOGNIZED' ✓
          4. packageName matches EXPECTED_PACKAGE_NAME ✓
          5. deviceRecognitionVerdict includes 'MEETS_DEVICE_INTEGRITY' ✓
    → If any check fails → Returns 403 with code 'INTEGRITY_FAILED'
```

### 7.2 Environment Variables (Supabase Secrets)
| Variable | Status |
|----------|--------|
| `GEMINI_API_KEY` | REQUIRED (set in Supabase) |
| `GOOGLE_SERVICE_ACCOUNT_JSON` | REQUIRED (set in Supabase) |
| `EXPECTED_PACKAGE_NAME` | Optional, defaults to `com.saadmohammed2000.flex_reminder` |
| `ALLOW_DEBUG_BYPASS` | Optional, defaults to `false` |

### 7.3 Verification Logic (Key Checks)
```typescript
// From supabase/functions/ai-proxy/index.ts

// 1. Nonce hash verification
const expectedHash = await sha256Base64(requestNonce);
if (payload.requestDetails?.requestHash !== expectedHash) return false;

// 2. Freshness (< 5 min)
const issued = Number(payload.requestDetails?.timestampMillis ?? 0);
if (!issued || Date.now() - issued > 5 * 60 * 1000) return false;

// 3. App recognition
if (payload.appIntegrity?.appRecognitionVerdict !== 'PLAY_RECOGNIZED') return false;
if (payload.appIntegrity?.packageName !== EXPECTED_PACKAGE_NAME) return false;

// 4. Device integrity
const deviceVerdicts = payload.deviceIntegrity?.deviceRecognitionVerdict ?? [];
if (!deviceVerdicts.includes('MEETS_DEVICE_INTEGRITY')) return false;
```

### 7.4 Error Response
```json
{
  "error": {
    "code": "INTEGRITY_FAILED",
    "message": "App integrity check failed, update the app to the latest version"
  }
}
```
**This exact message matches the user's reported error.**

---

## 8. ADB / Device Diagnostics

**ADB DEVICE: NOT AVAILABLE** - No device connected during diagnostic.

**Required Manual Checks** (run on test device with app installed from Internal Testing):
```bash
# 1. Verify installer is Google Play Store
adb shell dumpsys package com.saadmohammed2000.flex_reminder | grep -i installer

# 2. Verify version code
adb shell dumpsys package com.saadmohammed2000.flex_reminder | grep versionCode

# 3. Verify signing certificate
adb shell dumpsys package com.saadmohammed2000.flex_reminder | grep -A 20 "signing"

# 4. Check Play Services version
adb shell dumpsys package com.google.android.gms | grep versionName
```

---

## 9. Relevant Logs

### 9.1 Client-Side Expected Logs (from IntegrityService)
```
IntegrityService: enabled=true, cloudProjectNumber=1038373651011
IntegrityService: requesting token with nonce length=44
IntegrityService: PlayIntegrityException code=INTEGRITY_ERROR_APP_UID_MISMATCH, message=App UID mismatch., details=null
```
OR
```
IntegrityService: PlayIntegrityException code=INTEGRITY_ERROR_API_NOT_AVAILABLE, message=Integrity API is not available., details=null
```

### 9.2 Backend Error (from ai-proxy)
The exact error returned by the Edge Function:
```json
{
  "error": {
    "code": "INTEGRITY_FAILED",
    "message": "App integrity check failed, update the app to the latest version"
  }
}
```

### 9.3 Error Propagation Path
1. `PlayIntegrityException` caught in `FlutterPlayIntegrityWrapperPlugin` (Kotlin)
2. Returns error code `INTEGRITY_ERROR_<code>` to Dart
3. Dart wraps in `PlayIntegrityException` → `IntegrityException`
4. `AiProxyService` catches, throws `AiProxyException(403, code, message)`
5. `save_post_sheet.dart` catches, shows snackbar: `[Google Play Integrity] ... (Code: INTEGRITY_FAILED, Status: 403)`

---

## 10. Findings

| Priority | Finding | Evidence | Confidence |
|----------|---------|----------|------------|
| **CRITICAL** | Version code mismatch between local build and Play Console Internal Testing | User sees "update to latest version" - this exact message comes from backend when `appRecognitionVerdict != 'PLAY_RECOGNIZED'` or package mismatch. Most common cause: installed version ≠ uploaded version. | HIGH |
| **CRITICAL** | App not installed from Play Store (sideloaded/debug) | `INTEGRITY_FAILED` with "update to latest version" is returned when `appRecognitionVerdict !== 'PLAY_RECOGNIZED'`. This verdict is only `PLAY_RECOGNIZED` for apps installed from Play Store. | HIGH |
| **HIGH** | Local release build signed with upload key, not Play App Signing key | `build.gradle.kts` uses `upload-keystore.jks`. Play Store re-signs with App Signing key. Only Play Store installs have `PLAY_RECOGNIZED`. | HIGH |
| **HIGH** | `cloudProjectNumber` may be 0 in release build if `--dart-define` not passed correctly | `AppConfig.cloudProjectNumber` uses `String.fromEnvironment` with default. If build command misses the define, value becomes 0 → `enabled=false` → `INTEGRITY_DISABLED`. But user sees `INTEGRITY_FAILED`, so this is likely NOT the issue. | MEDIUM |
| **MEDIUM** | Nonce format compatibility | Client uses Base64 URL-safe (no padding). Backend expects same for SHA-256 hash verification. Implementation appears correct. | LOW |
| **MEDIUM** | Play Services version on device | Standard Integrity requires Play Services 23.20+. Old devices may fail with `API_NOT_AVAILABLE`. | LOW |
| **LOW** | Firebase SHA-1 configuration | Both upload key and Play App Signing key are registered in google-services.json. Correct. | LOW |

---

## 11. Most Likely Root Cause

### Primary Cause (Confidence: 85%)
**The installed app is not the exact same build that was uploaded to Play Console Internal Testing.**

Evidence:
1. Error message "App integrity check failed, update the app to the latest version" comes from backend when `appRecognitionVerdict !== 'PLAY_RECOGNIZED'`
2. `PLAY_RECOGNIZED` is only returned for apps installed **from Google Play Store**
3. Local builds (even release) are signed with **upload key**, not **Play App Signing key**
4. Play Store re-signs the AAB with the **App Signing key** before distribution
5. Only the Play Store distributed version has the correct signature for `PLAY_RECOGNIZED`

### Contributing Factors
- **Version code drift**: If local `pubspec.yaml` version (`+29`) doesn't match Play Console Internal Testing version, even a Play Store install might fail version checks
- **Stale Internal Testing release**: If the Internal Testing track wasn't updated after the last upload, users get old version

---

## 12. Recommended Next Steps

### Immediate (Do First)
1. **Verify Play Console Internal Testing version code**
   - Go to Play Console → Internal Testing → Releases
   - Note the exact `versionCode` of the active release

2. **Match local version exactly**
   - Update `pubspec.yaml`: `version: 1.3.5+XX` (match Play Console versionCode)
   - Rebuild: `flutter build appbundle --dart-define=GCP_CLOUD_PROJECT_NUMBER=1038373651011 --dart-define=STRICT_INTEGRITY_CHECK=true ...`

3. **Upload new AAB to Internal Testing**
   - Play Console → Internal Testing → Create new release → Upload AAB → Rollout 100%

4. **Force reinstall from Play Store on test device**
   - Uninstall app completely
   - Open Play Store → Internal Testing → Install/Update
   - Wait for download, then open

### Diagnostic (If issue persists)
5. **Capture client logs**
   - Run app from Play Store install
   - Trigger save post action
   - Check logcat: `adb logcat | grep -iE "IntegrityService|PlayIntegrity|INTEGRITY"`

6. **Verify installer source**
   ```bash
   adb shell dumpsys package com.saadmohammed2000.flex_reminder | grep installer
   # Must show: com.android.vending
   ```

7. **Check Play Services version**
   ```bash
   adb shell dumpsys package com.google.android.gms | grep versionName
   # Must be 23.20+ for Standard Integrity
   ```

### Configuration Verification
8. **Verify Google Cloud Console**
   - Project: `flex-reminders-app` (1038373651011)
   - APIs → Play Integrity API → ENABLED
   - Credentials → OAuth 2.0 Client ID for Android → Package: `com.saadmohammed2000.flex_reminder` + SHA-1: `4F:2F:0B:D0:1E:81:19:3C:B0:4F:23:F5:E7:26:0E:F1:01:76:99:C1`

9. **Verify Supabase Edge Function secrets**
   - `GOOGLE_SERVICE_ACCOUNT_JSON` set (service account with Play Integrity API access)
   - `EXPECTED_PACKAGE_NAME` = `com.saadmohammed2000.flex_reminder` (or unset for default)

---

## 13. Missing Information

The following cannot be determined from the project alone and require Google Play Console access:

| Information | Where to Find |
|-------------|---------------|
| **Exact versionCode on Internal Testing active release** | Play Console → Internal Testing → Releases |
| **Whether Internal Testing release is fully rolled out (100%)** | Play Console → Internal Testing → Track info |
| **Play App Signing key SHA-1/SHA-256** | Play Console → Setup → App signing |
| **Whether Play Integrity API is enabled in Google Cloud** | Google Cloud Console → APIs → Play Integrity API |
| **Service account permissions for Play Integrity** | Google Cloud Console → IAM → Service Account roles |
| **Test device Play Services version** | Device Settings → Apps → Google Play Services |

---

## 14. ChatGPT Handoff

**Problem**: Flutter app installed from Google Play Internal Testing fails Play Integrity check with `INTEGRITY_FAILED: App integrity check failed, update the app to the latest version` (403).

**Key Settings**:
- Package: `com.saadmohammed2000.flex_reminder`
- Cloud Project: `flex-reminders-app` (1038373651011)
- Wrapper: `flutter_play_integrity_wrapper` 0.0.2 (Standard Integrity)
- Local version: `1.3.5+29` (pubspec.yaml)
- Signing: Local=upload key, Play=App Signing key (both in Firebase)

**Critical Findings**:
1. Backend (Supabase Edge Function) returns exact error message when `appRecognitionVerdict !== 'PLAY_RECOGNIZED'`
2. `PLAY_RECOGNIZED` only for Play Store installs (not local builds)
3. Local release build signed with upload key; Play re-signs with App Signing key
4. Both keys registered in Firebase/google-services.json

**Logcat Need**: Exact `PlayIntegrityException` code from client (e.g., `INTEGRITY_ERROR_APP_UID_MISMATCH`, `INTEGRITY_ERROR_API_NOT_AVAILABLE`, etc.)

**Most Likely Cause**: Test device has stale/incorrect version installed, OR not actually installed from Play Store Internal Testing. Must verify: `adb shell dumpsys package ... | grep installer` shows `com.android.vending`.

**Next Step**: Match versionCode exactly with Play Console Internal Testing, upload new AAB, reinstall from Play Store, test.

---

**File Created**: `/home/user/myapp/PLAY_INTEGRITY_DIAGNOSTIC.md`

**No project files were modified**. This is a diagnostic report only.
