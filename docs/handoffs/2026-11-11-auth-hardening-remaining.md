# Handoff — auth hardening, remaining items

**To:** backend / office-web agent
**From:** mobile
**Date:** 2026-11-11
**ClickUp:** [P1][SEC] Auth hardening (`12493t4qztk`)

## Shipped on mobile

- The Drift SQLite database is now encrypted at rest with SQLCipher.
- A 32-byte key is generated once and stored in `flutter_secure_storage`
  (`tasktap.local_db_key.v1`, Keychain/Keystore-backed). It is per-installation, not per-user.
- Existing plaintext databases are migrated in place with `sqlcipher_export`; `user_version` is
  preserved so Drift does not re-run `onCreate`.
- If the key store or migration is unavailable, the app falls back to plaintext for that launch,
  reports to Sentry, and retries next launch. An encrypted DB with a lost key is discarded and
  resynced (unsent offline drafts are lost).
- Auth tokens were already in `flutter_secure_storage`; no change there.

## Remaining (not mobile)

1. **Zitadel MFA policy** for admin/office roles.
2. **Session and refresh lifetimes** — document the values and enforce them server-side.
3. **Web token storage** — currently `localStorage`; evaluate httpOnly-cookie/BFF against a strict
   CSP.
4. **Lost-device remote wipe/revoke** — a server-side per-device/session revoke endpoint, plus a
   signal the mobile client can act on: on a revoked/remote-wipe response, mobile should call its
   local `wipeAllData()` and delete `tasktap.local_db_key.v1` from secure storage. Coordinate the
   response shape with mobile.
5. **Device verification for SQLCipher** — a fresh install must produce a DB whose header is not
   `SQLite format 3\0`; a plaintext DB must migrate with rows intact; sync must work after the
   migration. This cannot be proven by the host test suite (the SQLCipher native library is a
   Flutter plugin), so it needs one Android/iOS device run before release.
