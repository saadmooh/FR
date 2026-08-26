# Paywall Security Plan — Preventing Subscription Bypass

> **Goal**: Ensure users cannot access any premium page/feature without an active subscription, even when the APK is modified, hooked at runtime (Frida), or run on rooted devices.
>
> **Scope**: Paywall enforcement (`lib/core/app_router.dart`), entitlement verification (`lib/services/revenuecat_service.dart`), backend enforcement (`supabase/functions/ai-proxy/index.ts`).

---

## 1. Current Architecture & Why It Is Bypassable

### 1.1 How the gate works today

| Component | Location | Role |
|---|---|---|
| Entitlement flag | `revenuecat_service.dart:16-18` | In-memory Dart bool `_isPremium`, derived from `customerInfo.entitlements.active.containsKey('pro')` |
| Router redirect | `app_router.dart:52-74` | Layer 2 of redirect: `!premium → /paywall`. Rebuilt via `refreshListenable: revenueCatService` |
| Purchase flow | `revenuecat_service.dart:74-90` | `Purchases.purchase(...)` → RevenueCat SDK → Google Play Billing |
| Server validation | `supabase/functions/ai-proxy/index.ts` | Play Integrity + auth + rate limits — but **never checks payment status** |

### 1.2 Attack vectors against this design

**A. Runtime memory patching (critical)**
The entire gate is one boolean read at `app_router.dart:65`. An attacker attaches Frida to the process and rewrites the return value of the `isPremium` getter — or NOPs the redirect condition. No root-level protection exists today; the app has no way to know it was tampered with.
*Reason this matters*: zero-cost bypass, works on every device, no repackaging needed.

**B. Static APK patching**
Decompile with apktool, flip the comparison in smali, re-sign with any key, install. The app never verifies its own signature at runtime.
*Reason*: the local data layer (ObjectBox) is fully functional offline — once inside, everything works because **all premium value is stored locally**.

**C. Refund / chargeback abuse within a session**
`_updatePremiumStatus()` runs at launch and on SDK listener events only. A user who buys, syncs, then refunds keeps full access until app restart. There is no periodic re-validation timer.

**D. Startup race**
If `RevenueCatService.initialize()` is slow (network delay), routes render before the first customer info arrives. As long as the default state is `false` (fail closed) this leaks nothing — but any future change that defaults optimistic would flash unlocked UI. Currently unverified/unprotected.

**E. Free ride on server resources**
The AI proxy enforces auth + Play Integrity + rate limits identically for free and paying users (`index.ts:640-899`). There is **no RevenueCat webhook**, so the Supabase backend has zero knowledge of who paid. A valid Play install gets AI features without ever paying.
*Reason this matters*: the subscription currently gates *nothing* of real server-side value — cracking the UI bool is the only thing worth doing, so attackers target exactly that.

**F. Leaked signing material (compounds every other issue)**
`upload-keystore.jks` (+ `.bak`), plaintext `storePassword`/`keyPassword` (`android/app/build.gradle.kts:35-42`), `sha1_fingerprints.txt`, and a GCP service-account JSON are committed to the repo. Anyone with these can sign a modified APK that passes the ai-proxy's own certificate pinning (`EXPECTED_CERT_SHA256`).
*Reason*: this neutralizes even the strong Play Integrity layer already built.

**G. Debug bypass header**
Client sends `X-Debug-Build: true` (`ai_proxy_service.dart:131-133`); server honors it when `allow_debug_bypass` is enabled (`index.ts:770-771`, default off). One config mistake away from an open door.

---

## 2. Threat Model & Honest Limits

| Attacker | Blocked by this plan? |
|---|---|
| Casual user sharing account / reinstall tricks | ✅ Yes |
| User who refunds after purchase | ✅ Yes (Layer 1+2) |
| User running patched APK on normal device | ✅ Mostly (Layer 2: no server token → empty/broken app) |
| Rooted device + Frida hooking the client | ⚠️ Raised cost drastically; local UI may still render but server-backed features fail |
| Attacker with repo access to signing keys | ❌ Must fix Phase 0 first |

**Principle**: a determined attacker can always patch a purely client-side check. The strategy is (a) move the source of truth off-device, (b) make the client prove subscription to the *backend*, and (c) ensure a patched client yields an app with nothing valuable in it.

---

## 3. The Plan

### Layer 0 — Stop the bleeding (immediate, ~half a day)

| # | Action | Reason |
|---|---|---|
| 0.1 | Remove from git history: `upload-keystore.jks`, `.bak`, `sha1_fingerprints.txt`, GCP service-account JSON, plaintext keystore passwords | These defeat the cert pinning in ai-proxy. Rotation alone is not enough if files stay in history — use `git filter-repo`, then rotate upload key via Play Console |
| 0.2 | Move signing config to env vars / CI secrets (`keystore.properties`, gitignored) | Prevents recurrence |
| 0.3 | Delete `X-Debug-Build` header (`ai_proxy_service.dart:131-133`) and the `allow_debug_bypass` branch (`index.ts`) | A single DB flag flip should never disable integrity checks |
| 0.4 | Strip release logging of user IDs / entitlements (`revenuecat_service.dart:22-31,48-58`), remove RC state overlay and integrity SnackBar dumps | Reduces recon information for attackers |

### Layer 1 — Harden the client-side gate (quick wins, ~1 day)

| # | Action | File(s) | Reason |
|---|---|---|---|
| 1.1 | Splash-gate startup: router emits only after `initialize()` completes | `main.dart:121`, `app_router.dart` | Closes race window D; guarantees first evaluation happens before any route renders |
| 1.2 | Fail closed on all errors: catch around entitlement refresh must resolve to `false` | `revenuecat_service.dart:_updatePremiumStatus` | Network failure / SDK error must show paywall, never unlock |
| 1.3 | Periodic re-validation timer: `Purchases.getCustomerInfo()` every 15 min; lapse → force `/paywall` | new code in `revenuecat_service.dart` | Kills refund-within-session vector C |
| 1.4 | Keep single choke point in go_router redirect; do not scatter `isPremium` checks through screens | `app_router.dart:65` | One auditable gate beats N forgettable ones |
| 1.5 | Obfuscation: enable R8 `minifyEnabled true` + resource shrinking in release | `android/app/build.gradle.kts` | Removes trivially findable symbols like `RevenueCatService.isPremium`; raises effort for vector A/B |

*Why Layer 1 is not enough*: R8 slows attackers down; it does not stop them. The bool still lives in memory on an untrusted device. Real enforcement requires the backend.

### Layer 2 — Move trust off-device (core fix, ~2–3 days)

| # | Action | Reason |
|---|---|---|
| 2.1 | **RevenueCat webhook** → new edge function `supabase/functions/revenuecat-webhook/index.ts`. Verify RC webhook auth signature; handle `INITIAL_PURCHASE`, `RENEWAL`, `PRODUCT_CHANGE`, `EXPIRATION`, `BILLING_ISSUE`, `REFUND_REVERSED` (as applicable); upsert into new table `entitlements(user_id uuid pk/fk, product_id text, expires_at timestamptz, status text, updated_at)` keyed by the Firebase UID already passed as `appUserID` (`revenuecat_service.dart:92-122`) | Backend finally knows who paid. Webhook signature verification prevents forged "purchase" events. This is the missing piece that makes every later check possible |
| 2.2 | **Session-token endpoint**: new edge function. Client presents Firebase JWT + fresh Play Integrity token (reuse `integrity_service.dart` nonce scheme). Server validates integrity verdicts (same logic as ai-proxy), reads `entitlements`, returns short-lived signed JWT (~60 min) containing `uid`, `entitlement:'pro'`, `exp` | The paywall gate becomes "hold a valid unexpired signed token" instead of "a mutable bool says so". Patched clients cannot mint tokens; refunds/cancellations revoke access within minutes server-side |
| 2.3 | Router consumes token: `isPremium` ⇒ valid, unexpired session token held in secure storage; silent refresh on expiry; loss of token → redirect to `/paywall` | Even if an attacker hooks the local bool, server calls fail without a token, degrading the app to unusable rather than merely cosmetic unlock |
| 2.4 | Gate the AI proxy by the same table: after integrity checks in `index.ts`, require active entitlement row for the caller's UID | Today free users get full AI quota without paying — closes vector E and makes the subscription actually protect server value |
| 2.5 | Clock-skew safety: validate `exp` server-side everywhere; client treats "cannot reach server" as *not premium* after a grace period (e.g., 24h cached grace for UX) | Prevents both replay attacks and punishing offline legitimate users too harshly |

### Layer 3 — Tamper resistance (raise attack cost, ~1 day)

| # | Action | Reason |
|---|---|---|
| 3.1 | Require fresh Play Integrity verdict for the 2.2 endpoint (already built: nonce binding `integrity_service.dart:28-43`, single-use table, cert pinning) | Patched/cloned/re-signed installs cannot obtain tokens at all — the strongest practical barrier |
| 3.2 | Basic environment checks at launch: root indicators, debugger attached, suspicious frida artifacts → log + fail closed to paywall | Not bulletproof; adds friction and gives telemetry that tampering is occurring |
| 3.3 | Certificate pinning for calls to your own Supabase functions | Blocks trivial MITM of the token exchange |
| 3.4 | Split sensitive strings/logic across modules; avoid obvious names near the gate | Marginal obfuscation on top of R8 |

### Layer 4 — Optional nuclear option: make bypass worthless (~2 days, evaluate ROI)

| # | Action | Reason |
|---|---|---|
| 4.1 | Encrypt ObjectBox stores with an AES key delivered only inside the Layer-2 session token response; store key in `flutter_secure_storage` per-session | A cracked APK opens an app whose local database is ciphertext — there is literally nothing to use. This converts "annoying to bypass" into "pointless to bypass". Trade-off: complexity + what happens to offline-first UX during grace periods |

---

## 4. Implementation Order

```
Phase 0  (day 0)      Secrets removal + rotation, debug header removal        ← do immediately
Phase 1  (day 1)      1.1–1.5 client hardening                                ← quick wins
Phase 2  (days 2–4)   2.1 webhook + table
                      2.2 token endpoint (+ 3.1 integrity requirement)
                      2.3 router switch-over
                      2.4 AI proxy entitlement gate
Phase 3  (day 5)      3.2–3.4 hardening extras
Phase 4  (optional)   4.1 encrypted local store                               ← decide based on threat model
```

Dependency notes:
- 2.2 depends on 2.1 (needs the `entitlements` table).
- 2.3 depends on 2.2; ship behind a remote-config kill switch so the old bool path can be restored instantly if something breaks in production.
- 2.4 is independent once 2.1 lands.

## 5. Testing Checklist

- [ ] Fresh install, never purchased → locked to `/paywall`, AI proxy returns 403
- [ ] Sandbox purchase → unlock within seconds, all pages reachable
- [ ] Refund in Play Console → access revoked ≤ 15 min without app restart
- [ ] Airplane mode at launch → paywall (fail closed); airplane mode mid-session → grace behavior per 2.5
- [ ] Token expired mid-session → silent refresh; refresh fails → paywall
- [ ] Replayed/old nonce to token endpoint → rejected (single-use table)
- [ ] Modified APK (smali-patched bool) → passes local gate but token endpoint refuses → server features dead
- [ ] Webhook forgery (no/wrong signature) → 401, no table mutation
- [ ] Expiration webhook → row updated, next token request denied
- [ ] Release build with R8 → all flows above still pass

## 6. Residual Risk Acceptance

After Layers 0–3: a skilled attacker on a rooted device with Frida may still see premium *UI* locally, but obtains no server value (AI, sync, backup, any future API), holds no valid token, and their install fails Play Integrity. Combined with Layer 4, remaining incentive approaches zero. This is the practical ceiling for any client-distributed app; beyond it lies attested execution/hardware attestation territory with diminishing returns.
