// dart format width=100
import 'dart:async';
import 'dart:io';

import 'package:sentry_flutter/sentry_flutter.dart';
import 'package:sqlite3/sqlite3.dart';

import 'local_database_key_store.dart';

enum LocalDatabaseOpenMode { encrypted, plaintextFallback }

class LocalDatabaseOpenPlan {
  const LocalDatabaseOpenPlan({
    required this.file,
    required this.keyHex,
    required this.mode,
    this.migrated = false,
  });

  final File file;

  /// Null only in [LocalDatabaseOpenMode.plaintextFallback].
  final String? keyHex;
  final LocalDatabaseOpenMode mode;

  /// True when a pre-existing plaintext DB was migrated during this open.
  final bool migrated;
}

/// The raw SQLCipher operations. Separated so the decision logic is testable without the native
/// SQLCipher library (which only ships in the Flutter plugin, not the host test runner).
abstract interface class LocalDatabaseCipher {
  /// Whether the linked native library is actually SQLCipher (not plain sqlite3, where `PRAGMA
  /// key` would be ignored and the file would stay plaintext).
  Future<bool> isAvailable();

  Future<void> migratePlaintext(File source, String keyHex);

  Future<bool> verify(File file, String keyHex);
}

abstract interface class LocalDatabaseErrorReporter {
  void report(Object error, StackTrace stack);
}

class SentryLocalDatabaseErrorReporter implements LocalDatabaseErrorReporter {
  const SentryLocalDatabaseErrorReporter();

  @override
  void report(Object error, StackTrace stack) {
    unawaited(
      Sentry.captureException(
        error,
        stackTrace: stack,
        withScope: (scope) async {
          await scope.setTag('area', 'local-db-encryption');
        },
      ),
    );
  }
}

/// Decides how this launch opens the local database: encrypted, migrated from plaintext, or a
/// plaintext fallback when the key or migration is unavailable.
class LocalDatabaseEncryption {
  LocalDatabaseEncryption({
    required this.keyStore,
    LocalDatabaseCipher? cipher,
    LocalDatabaseErrorReporter? reporter,
  }) : cipher = cipher ?? SqlCipherDatabaseCipher(),
       reporter = reporter ?? const SentryLocalDatabaseErrorReporter();

  final LocalDatabaseKeyStore keyStore;
  final LocalDatabaseCipher cipher;
  final LocalDatabaseErrorReporter reporter;

  Future<LocalDatabaseOpenPlan> prepare(File file) async {
    String? key;
    try {
      key = await keyStore.loadOrCreate();
    } catch (e, s) {
      reporter.report(e, s);
    }

    bool cipherAvailable;
    try {
      cipherAvailable = await cipher.isAvailable();
    } catch (_) {
      cipherAvailable = false;
    }
    if (!cipherAvailable) {
      reporter.report(
        StateError('SQLCipher is not available; the local database cannot be encrypted.'),
        StackTrace.current,
      );
      final existsForCheck = await file.exists();
      final plaintextForCheck = existsForCheck && await isPlaintextDatabase(file);
      if (existsForCheck && !plaintextForCheck) {
        throw StateError('Local database is encrypted but SQLCipher is unavailable.');
      }
      return LocalDatabaseOpenPlan(
        file: file,
        keyHex: null,
        mode: LocalDatabaseOpenMode.plaintextFallback,
      );
    }

    final exists = await file.exists();
    if (!exists) {
      return LocalDatabaseOpenPlan(
        file: file,
        keyHex: key,
        mode: key == null
            ? LocalDatabaseOpenMode.plaintextFallback
            : LocalDatabaseOpenMode.encrypted,
      );
    }

    final plaintext = await isPlaintextDatabase(file);

    if (plaintext) {
      if (key == null) {
        return LocalDatabaseOpenPlan(
          file: file,
          keyHex: null,
          mode: LocalDatabaseOpenMode.plaintextFallback,
        );
      }
      try {
        await cipher.migratePlaintext(file, key);
        return LocalDatabaseOpenPlan(
          file: file,
          keyHex: key,
          mode: LocalDatabaseOpenMode.encrypted,
          migrated: true,
        );
      } catch (e, s) {
        reporter.report(e, s);
        return LocalDatabaseOpenPlan(
          file: file,
          keyHex: null,
          mode: LocalDatabaseOpenMode.plaintextFallback,
        );
      }
    }

    // Encrypted file. Without the key it cannot be read; never silently downgrade it to plaintext.
    if (key == null) {
      throw StateError('Local database is encrypted but its key is unavailable.');
    }

    bool valid;
    try {
      valid = await cipher.verify(file, key);
    } catch (e, s) {
      reporter.report(e, s);
      valid = false;
    }
    if (valid) {
      return LocalDatabaseOpenPlan(
        file: file,
        keyHex: key,
        mode: LocalDatabaseOpenMode.encrypted,
      );
    }

    // Key lost/corrupt (or a restored backup without its keystore entry). The file is
    // unrecoverable; start a fresh encrypted one and let sync repopulate the mirror.
    reporter.report(
      StateError('Encrypted local database could not be opened with the stored key; recreating.'),
      StackTrace.current,
    );
    try {
      await file.delete();
    } catch (_) {
      // If the delete fails, the Drift open will surface the real error.
    }
    return LocalDatabaseOpenPlan(
      file: file,
      keyHex: key,
      mode: LocalDatabaseOpenMode.encrypted,
    );
  }
}

/// True only for a file that starts with SQLite's plaintext header. SQLCipher files begin with a
/// random 16-byte salt and never match it.
Future<bool> isPlaintextDatabase(File file) async {
  final raf = await file.open();
  try {
    final header = await raf.read(16);
    return header.length == 16 && String.fromCharCodes(header) == 'SQLite format 3\u0000';
  } finally {
    await raf.close();
  }
}

class SqlCipherDatabaseCipher implements LocalDatabaseCipher {
  const SqlCipherDatabaseCipher();

  @override
  Future<bool> isAvailable() async {
    try {
      final db = sqlite3.openInMemory();
      try {
        return db.select('PRAGMA cipher_version;').isNotEmpty;
      } finally {
        db.dispose();
      }
    } catch (_) {
      return false;
    }
  }

  @override
  Future<void> migratePlaintext(File source, String keyHex) async {
    final temp = File('${source.path}.enc.tmp');
    if (temp.existsSync()) temp.deleteSync();

    final db = sqlite3.open(source.path);
    try {
      // Fold any WAL back into the main file before copying; otherwise committed frames in
      // `tasktap.db-wal` would be left behind and later applied to the encrypted file with the
      // same name.
      db.execute('PRAGMA wal_checkpoint(TRUNCATE);');
      final version = (db.select('PRAGMA user_version').first.values.first as int?) ?? 0;
      db.execute(
        "ATTACH DATABASE '${_escapeSqlPath(temp.path)}' AS encrypted KEY \"x'$keyHex'\";",
      );
      db.execute("SELECT sqlcipher_export('encrypted');");
      db.execute('PRAGMA encrypted.user_version = $version;');
      db.execute('DETACH DATABASE encrypted;');
    } finally {
      db.dispose();
    }

    _deleteSidecars(source);

    if (!await verify(temp, keyHex)) {
      temp.deleteSync();
      throw StateError('The encrypted database copy did not verify.');
    }
    _deleteSidecars(temp);

    // POSIX rename replaces the destination atomically; the plaintext file is gone in the same
    // step the verified encrypted file takes its place.
    temp.renameSync(source.path);
  }

  @override
  Future<bool> verify(File file, String keyHex) async {
    try {
      final db = sqlite3.open(file.path);
      try {
        db.execute("PRAGMA key = \"x'$keyHex'\";");
        db.select('SELECT count(*) FROM sqlite_master');
        db.execute('PRAGMA wal_checkpoint(TRUNCATE);');
        return true;
      } finally {
        db.dispose();
      }
    } catch (_) {
      return false;
    }
  }

  static String _escapeSqlPath(String path) => path.replaceAll("'", "''");

  /// SQLite sidecars belong to the plaintext DB; leaving them next to a renamed encrypted file
  /// would let them be replayed against it.
  static void _deleteSidecars(File file) {
    for (final suffix in const ['-wal', '-shm', '-journal']) {
      final sidecar = File('${file.path}$suffix');
      if (sidecar.existsSync()) sidecar.deleteSync();
    }
  }
}
