# Mobile local-DB encryption — design

Status: **Draft, for review.**

ClickUp: [P1][SEC] Auth hardening — mobile local-DB encryption (`12493t4qztk`).

## Intent

The Drift SQLite database holds offline reports, drafts, customers and attendance data in plain
text. Encrypt it at rest with SQLCipher and a device-held key. The rest of that ClickUp task (MFA,
session lifetimes, web token storage, lost-device revoke) stays with the backend/web agent.

## Current state

- `AppDatabase` opens `tasktap.db` via `NativeDatabase.createInBackground(file)`
  (`lib/data/local/app_database.dart:2853`), schema v62.
- Native SQLite comes from `sqlite3_flutter_libs`.
- Tokens already live in `flutter_secure_storage`; the DB file is the gap.

## Approach

**SQLCipher + in-place migration (chosen).**

- Replace `sqlite3_flutter_libs` with `sqlcipher_flutter_libs: ^0.6.8` (0.7.0 is an end-of-life
  no-op and would leave no native SQLite library) and add `sqlite3` as a direct dependency for the
  migration/verification helpers. On Android, point `package:sqlite3` at `libsqlcipher.so` with
  `open.overrideFor(OperatingSystem.android, openCipherOnAndroid)` in `main`, and verify
  `PRAGMA cipher_version` is non-empty before using a key.
- Generate a 32-byte random key on first open, hex-encode it, store it in secure storage
  (`tasktap.local_db_key.v1`). Apply `PRAGMA key = "x'<hex>'"` in the Drift `setup` callback.
- Existing plaintext DB: detect the `SQLite format 3\0` header, copy to a temp encrypted file with
  `ATTACH … KEY` + `sqlcipher_export()`, preserve `PRAGMA user_version`, verify the temp file opens
  with the key, then atomically replace the original. No plaintext backup is left behind.
- New install: the key is applied before Drift creates the schema, so the file is encrypted from
  the first write.

Rejected: new-installs-only (loses offline drafts/queue on upgrade); field-level encryption (not
whole-DB, leaves structure/metadata readable); OS file protection alone (already in place).

## Failure policy (approved)

- **Key store unavailable, DB plaintext or missing:** fall back to plaintext for this launch,
  report to Sentry, retry next launch.
- **Migration fails:** keep the plaintext DB, fall back, report to Sentry, retry next launch.
- **Key store unavailable, DB encrypted:** cannot decrypt. Fail this open with a clear error rather
  than silently downgrade; report to Sentry. (Hardware/keystore failure, not a normal path.)
- **Encrypted DB cannot be opened with the stored key** (key lost, backup restored without its
  keystore entry, corruption): delete the DB and start a fresh encrypted one; sync repopulates the
  mirror. Unsent offline drafts are lost — documented and reported.
- **Lost-device revoke / remote wipe:** out of this slice; handoff to backend.

## Key handling

- 32 bytes from `Random.secure()`, 64 lowercase hex chars.
- Stored with `flutter_secure_storage` (Keychain/Keystore), same store the auth tokens use.
- The key is per-device, not per-user; the DB is a per-device mirror plus local drafts.
- No key rotation in this pass.

## Sqlcipher specifics

- `PRAGMA key = "x'<hex>'"` (raw key) for both Drift and the migration/verification connection.
- Migration:
  ```sql
  ATTACH DATABASE '<temp>' AS encrypted KEY "x'<hex>'";
  SELECT sqlcipher_export('encrypted');
  PRAGMA encrypted.user_version = <plaintext user_version>;
  DETACH DATABASE encrypted;
  ```
- Verify: open the temp with the key, `SELECT count(*) FROM sqlite_master`.
- Replace only after verification; delete the plaintext file and rename the temp.
- The migration runs on the main isolate before `createInBackground`; the key is passed to the
  isolate via the Drift `setup` closure (a sendable String).

## Files

- Modify: `pubspec.yaml` (swap native libs, add `sqlite3`).
- New: `lib/data/local/local_database_key_store.dart` (key generation/storage).
- New: `lib/data/local/local_database_encryption.dart` (header detection, migrate, verify, open).
- Modify: `lib/data/local/app_database.dart` — `_openConnection` delegates to the new opener.
- Test: `test/data/local/local_database_key_store_test.dart` (fake secure storage).
- Test: `test/data/local/local_database_encryption_test.dart` (header detection + orchestration with
  injected fakes).
- Docs/handoff for the remaining security items.

## Testing

Host tests cannot load `sqlcipher_flutter_libs` (it is a Flutter plugin), so:
- Unit-test key generation/persistence, header detection, and the migration/fallback orchestration
  with an injected migrator/verifier.
- Add a device/integration check (manual for now): fresh install creates an encrypted file
  (different header from `SQLite format 3`), an existing plaintext DB is migrated with rows intact,
  and the app still syncs after migration.
- `flutter analyze` + the affected DB/unit suites; an Android/iOS build is required to validate the
  native-library swap (CI/codemagic).

## Residual risks

- A restored iOS/Android backup may restore the encrypted DB without the Keychain/Keystore key; that
  path is handled by discarding and resyncing, losing unsent drafts.
- SQLCipher adds a small open/read cost; no benchmark target in this pass.
- The host suite cannot prove the native encryption path; a device run is required before merge.

## Handoff (not in this slice)

- Backend/web: MFA for privileged roles, session/refresh lifetimes, web token storage (httpOnly/BFF
  vs CSP), and a lost-device remote wipe/revoke flow.
