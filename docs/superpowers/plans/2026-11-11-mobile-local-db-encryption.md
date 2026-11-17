# Mobile local-DB encryption — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Encrypt the mobile Drift database at rest with SQLCipher, migrate the existing plaintext DB in place, and keep the key in secure storage.

**Architecture:** Swap `sqlite3_flutter_libs` for `sqlcipher_flutter_libs`. A new `LocalDatabaseEncryption` decides between plaintext, migrated and encrypted openings; a `LocalDatabaseKeyStore` generates/persists the key; `_openConnection` applies `PRAGMA key` through Drift's `setup` callback.

**Tech Stack:** Flutter, Drift, `sqlite3` (SQLCipher), `flutter_secure_storage`, Sentry.

**Spec:** `docs/superpowers/specs/2026-11-11-mobile-local-db-encryption-design.md`

## Global Constraints

- Key: 32 random bytes, 64 lowercase hex chars, stored under `tasktap.local_db_key.v1` in `flutter_secure_storage`.
- Apply the key with `PRAGMA key = "x'<hex>'"`.
- Never leave a plaintext backup after a successful migration.
- Failure policy: fallback to plaintext + Sentry + retry on key-store/migration failure; encrypted DB with a bad/missing key → delete and recreate encrypted; key-store failure with an encrypted DB → throw clearly.
- No key rotation, no lost-device wipe/revoke in this slice (handoff).
- Do not commit or push unless asked.

## Review Focus

- A plaintext DB must be migrated only after the encrypted temp verifies; the plaintext file must not be deleted before that.
- `PRAGMA user_version` must survive migration, or Drift would run `onCreate` against an existing schema.
- A failed migration must leave the original plaintext DB usable and retry on the next launch.
- An encrypted DB opened with a wrong/lost key must not silently become a new plaintext DB.
- Host tests must not require SQLCipher native libs.

---

### Task 1: Dependencies and the key store

**Files:**
- Modify: `pubspec.yaml` (swap native libs, add `sqlite3`), `lib/main.dart` (Android SQLCipher override)
- Create: `lib/data/local/local_database_key_store.dart`
- Test: `test/data/local/local_database_key_store_test.dart`

**Interfaces:**
- Produces: `abstract interface class LocalDatabaseKeyStore { Future<String> loadOrCreate(); }`; `class SecureLocalDatabaseKeyStore implements LocalDatabaseKeyStore`.

- [ ] **Step 1: Add the failing key-store tests**

```dart
test('generates a 64-char lowercase hex key and persists it', () async {
  final storage = _FakeSecureStorage();
  final store = SecureLocalDatabaseKeyStore(storage);
  final key = await store.loadOrCreate();
  expect(key, matches(RegExp(r'^[0-9a-f]{64}$')));
  expect(storage.values['tasktap.local_db_key.v1'], key);
});

test('reuses an existing key', () async {
  final storage = _FakeSecureStorage()..values['tasktap.local_db_key.v1'] = 'a' * 64;
  final store = SecureLocalDatabaseKeyStore(storage);
  expect(await store.loadOrCreate(), 'a' * 64);
});

test('replaces a malformed stored key', () async {
  final storage = _FakeSecureStorage()..values['tasktap.local_db_key.v1'] = 'short';
  final key = await SecureLocalDatabaseKeyStore(storage).loadOrCreate();
  expect(key, matches(RegExp(r'^[0-9a-f]{64}$')));
});
```

Use a fake around `FlutterSecureStorage`? Prefer an interface:
```dart
abstract interface class SecureStringStore {
  Future<String?> read(String key);
  Future<void> write(String key, String value);
}
class FlutterSecureStringStore implements SecureStringStore { ... const FlutterSecureStorage ... }
```
`SecureLocalDatabaseKeyStore` takes a `SecureStringStore`; tests use an in-memory fake. Keep the real store in the same file.

- [ ] **Step 2: Run them to verify they fail**

Run: `flutter test test/data/local/local_database_key_store_test.dart`
Expected: FAIL — classes undefined.

- [ ] **Step 3: Add dependencies and implement the key store**

`pubspec.yaml`: remove `sqlite3_flutter_libs`, add `sqlcipher_flutter_libs: ^0.6.8` (0.7.0 is an EOL no-op) and `sqlite3: ^2.9.4`.

Implement:
```dart
class SecureLocalDatabaseKeyStore implements LocalDatabaseKeyStore {
  SecureLocalDatabaseKeyStore([SecureStringStore? store])
      : _store = store ?? const FlutterSecureStringStore();
  static const keyName = 'tasktap.local_db_key.v1';
  @override
  Future<String> loadOrCreate() async {
    final existing = await _store.read(keyName);
    if (existing != null && RegExp(r'^[0-9a-f]{64}$').hasMatch(existing)) return existing;
    final key = List<int>.generate(32, (_) => Random.secure().nextInt(256))
        .map((b) => b.toRadixString(16).padLeft(2, '0'))
        .join();
    await _store.write(keyName, key);
    return key;
  }
}
```

- [ ] **Step 4: Run the key-store tests**

Run: `flutter test test/data/local/local_database_key_store_test.dart`
Expected: PASS.

---

### Task 2: Encryption helper and migration orchestration

**Files:**
- Create: `lib/data/local/local_database_encryption.dart`
- Test: `test/data/local/local_database_encryption_test.dart`

**Interfaces:**
- Produces:
  - `enum LocalDatabaseOpenMode { encrypted, plaintextFallback }`
  - `class LocalDatabaseOpenPlan { final File file; final String? keyHex; final bool migrated; final LocalDatabaseOpenMode mode; }`
  - `abstract interface class LocalDatabaseCipher { Future<void> migratePlaintext(File source, String keyHex); Future<bool> verify(File file, String keyHex); }`
  - `abstract interface class LocalDatabaseErrorReporter { void report(Object error, StackTrace stack); }`
  - `class LocalDatabaseEncryption { LocalDatabaseEncryption({required LocalDatabaseKeyStore keyStore, LocalDatabaseCipher? cipher, LocalDatabaseErrorReporter? reporter}); Future<LocalDatabaseOpenPlan> prepare(File file); }`
  - `class SqlCipherDatabaseCipher implements LocalDatabaseCipher` (uses `package:sqlite3/sqlite3.dart`).
  - `class SentryLocalDatabaseErrorReporter implements LocalDatabaseErrorReporter`.

- [ ] **Step 1: Add the failing orchestration tests**

Use a temp directory, a fake key store, a fake cipher, and a fake reporter:
```dart
test('a missing file opens encrypted with the generated key', ...);
test('a plaintext file is migrated when the cipher succeeds', ...);
test('a failed migration leaves the plaintext file and falls back', ...);
test('an encrypted file with a valid key stays encrypted', ...);
test('an encrypted file with an invalid key is deleted and recreated', ...);
test('a key-store failure on a plaintext file falls back to plaintext', ...);
test('a key-store failure on an encrypted file throws', ...);
test('isPlaintextDatabase recognises the SQLite header only', ...);
```
Write the header with `File(...).writeAsBytesSync(utf8.encode('SQLite format 3\u0000'))` for plaintext and random bytes for encrypted.

- [ ] **Step 2: Run them to verify they fail**

Run: `flutter test test/data/local/local_database_encryption_test.dart`
Expected: FAIL — classes undefined.

- [ ] **Step 3: Implement `LocalDatabaseEncryption`**

`prepare`:
1. `final key = await keyStore.loadOrCreate()` (catch → key-store failure path).
2. If the file does not exist → `encrypted` plan with key.
3. `plaintext = isPlaintextDatabase(file)`.
4. Plaintext + key:
   - `try { await cipher.migratePlaintext(file, key); } catch (e) { reporter.report; return plaintextFallback; }`
   - After migrate, `mode = encrypted`, `migrated = true`.
5. Plaintext + key-store failure → `plaintextFallback`.
6. Encrypted:
   - If key available and `await cipher.verify(file, key)` → encrypted.
   - If verification fails → `file.delete()`, reporter, return encrypted with the key (new file).
   - If key-store failure → throw `StateError('local database is encrypted but its key is unavailable')`.

- [ ] **Step 4: Implement `SqlCipherDatabaseCipher`**

```dart
Future<void> migratePlaintext(File source, String keyHex) async {
  final temp = File('${source.path}.enc.tmp');
  if (temp.existsSync()) temp.deleteSync();
  final db = sqlite3.open(source.path);
  try {
    final version = (db.select('PRAGMA user_version').first.values.first as int?) ?? 0;
    db.execute("ATTACH DATABASE '${_escapeSqlPath(temp.path)}' AS encrypted KEY \"x'$keyHex'\";");
    db.execute("SELECT sqlcipher_export('encrypted');");
    db.execute('PRAGMA encrypted.user_version = $version;');
    db.execute('DETACH DATABASE encrypted;');
  } finally {
    db.dispose();
  }
  if (!await verify(temp, keyHex)) {
    temp.deleteSync();
    throw StateError('encrypted copy did not verify');
  }
  source.deleteSync();
  temp.renameSync(source.path);
}

Future<bool> verify(File file, String keyHex) async {
  try {
    final db = sqlite3.open(file.path);
    try {
      db.execute("PRAGMA key = \"x'$keyHex'\";");
      db.select('SELECT count(*) FROM sqlite_master');
      return true;
    } finally {
      db.dispose();
    }
  } catch (_) {
    return false;
  }
}
```
`_escapeSqlPath` doubles single quotes.

- [ ] **Step 5: Run the orchestration tests**

Run: `flutter test test/data/local/local_database_encryption_test.dart`
Expected: PASS.

---

### Task 3: Wire it into the app database

**Files:**
- Modify: `lib/data/local/app_database.dart:2851-2858` (`_openConnection`)
- Test: `test/data/local/app_database_opening_test.dart` (plan-level, not the native path)

**Interfaces:**
- Consumes: `LocalDatabaseEncryption`, `SecureLocalDatabaseKeyStore`, `LocalDatabaseOpenPlan`.
- Produces: encrypted `QueryExecutor` with the key applied in `setup`.

- [ ] **Step 1: Replace `_openConnection`**

```dart
LazyDatabase _openConnection() {
  return LazyDatabase(() async {
    final dbFolder = await getApplicationDocumentsDirectory();
    final file = File(p.join(dbFolder.path, 'tasktap.db'));
    final plan = await LocalDatabaseEncryption(
      keyStore: SecureLocalDatabaseKeyStore(),
    ).prepare(file);
    return NativeDatabase.createInBackground(
      file,
      setup: plan.keyHex == null
          ? null
          : (db) => db.execute("PRAGMA key = \"x'${plan.keyHex}'\";"),
    );
  });
}
```

- [ ] **Step 2: Add a plan-level test**

Test that `prepare` returns `encrypted` for a fresh file and `plaintextFallback` when the key store
throws with a plaintext file (reuse Task 2's fakes; no native SQLCipher required).

- [ ] **Step 3: Run analysis and the affected tests**

```bash
flutter analyze
flutter test test/data/local/local_database_key_store_test.dart test/data/local/local_database_encryption_test.dart test/data/local
```
Expected: PASS.

---

### Task 4: Docs, handoff and verification

**Files:**
- Add: `docs/superpowers/specs/2026-11-11-mobile-local-db-encryption-design.md` (already drafted)
- Add: `docs/handoffs/2026-11-11-auth-hardening-remaining.md` (MFA, sessions, web tokens, lost-device revoke)
- Add: `docs/superpowers/plans/2026-11-11-mobile-local-db-encryption.md` (this plan)

- [ ] **Step 1: Write the remaining-items handoff**

State that the mobile slice is local-DB encryption only; backend/web own MFA for privileged roles,
session/refresh lifetimes, web token storage (httpOnly/BFF vs CSP), and the lost-device remote
wipe/revoke flow.

- [ ] **Step 2: Verify**

Run:
```bash
flutter analyze
flutter test test/data/local test/contract
```
Expected: PASS. The native SQLCipher path still requires a device/integration run (fresh install
creates a non-`SQLite format 3` file; a plaintext DB migrates with rows intact; sync works after).

- [ ] **Step 3: Report, do not commit**

Report changed files, test/analyze output, the device-verification requirement, and the handoff.
