# Project Memory

## Account-fraud incident (Sept 2026)
- Abuse pattern: bulk Google accounts named `firstname.lastname.NNNNN@gmail.com` signing in via Firebase, which auto-provisions Supabase `auth.users` rows.
- Root cause: `lib/widgets/save_post_sheet.dart` uses `signInWithIdToken(OAuthProvider('custom:firebase'))`. GoTrue silently creates an `auth.users` row for every unseen Firebase UID — no signup form, no rate limit. **Deleting rows does not close the door**; accounts re-appear while the app is still installed.
- RevenueCat project id: `proj9337f6cb` (not in repo; lives in Supabase secrets). Kept distinct from `xwgckczyihcgydcrfzel` (Supabase) and `flex-reminders-app` (Firebase).

## Operational gotchas (cost real debugging time)
- `identitytoolkit.googleapis.com/v1/.../accounts:query` returns **0 users even when users exist**. Trust only the Firebase Admin SDK `listUsers()`. v1 `accounts:lookup` returns `MISSING_ID_TOKEN` because it wants an ID token, not a service-account access token — that also looks like "no users".
- `admin.auth().deleteUsers()` returns `{successCount, errors}`, **not an array** — spreading it throws *after* the delete already succeeded.
- RevenueCat v2 `DELETE /customers/{id}` is eventually consistent; two accounts still appeared in a post-delete listing and vanished on the next poll. Always re-list and retry.
- Entitlement identity is the **Firebase UID** (`entitlements.user_id` is TEXT, no FK to `auth.users`), so deleting auth rows never touches paid entitlements — they must be cleaned separately.
