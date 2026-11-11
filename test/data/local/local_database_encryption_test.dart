// test/data/local/local_database_encryption_test.dart
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:tasktap_mobile/data/local/local_database_encryption.dart';
import 'package:tasktap_mobile/data/local/local_database_key_store.dart';

const _key = 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';

class _FakeKeyStore implements LocalDatabaseKeyStore {
  _FakeKeyStore({this.throwOnLoad = false});

  final bool throwOnLoad;

  @override
  Future<String> loadOrCreate() async {
    if (throwOnLoad) throw StateError('keystore unavailable');
    return _key;
  }
}

class _FakeCipher implements LocalDatabaseCipher {
  bool verifyResult = true;
  bool throwOnMigrate = false;
  bool available = true;
  int migrateCalls = 0;
  int verifyCalls = 0;

  @override
  Future<bool> isAvailable() async => available;

  @override
  Future<void> migratePlaintext(File source, String keyHex) async {
    migrateCalls++;
    if (throwOnMigrate) throw StateError('migration failed');
  }

  @override
  Future<bool> verify(File file, String keyHex) async {
    verifyCalls++;
    return verifyResult;
  }
}

class _FakeReporter implements LocalDatabaseErrorReporter {
  final errors = <Object>[];

  @override
  void report(Object error, StackTrace stack) => errors.add(error);
}

void main() {
  late Directory dir;
  late File file;

  setUp(() {
    dir = Directory.systemTemp.createTempSync('tt-db-encryption-');
    file = File('${dir.path}/tasktap.db');
  });

  tearDown(() {
    if (dir.existsSync()) dir.deleteSync(recursive: true);
  });

  LocalDatabaseEncryption encryption({
    LocalDatabaseKeyStore? keyStore,
    LocalDatabaseCipher? cipher,
    LocalDatabaseErrorReporter? reporter,
  }) => LocalDatabaseEncryption(
    keyStore: keyStore ?? _FakeKeyStore(),
    cipher: cipher ?? _FakeCipher(),
    reporter: reporter ?? _FakeReporter(),
  );

  void writePlaintext() => file.writeAsBytesSync(utf8.encode('SQLite format 3\u0000'));

  void writeEncrypted() => file.writeAsBytesSync(List<int>.generate(16, (i) => i + 7));

  test('a missing file opens encrypted with the generated key', () async {
    final plan = await encryption().prepare(file);

    expect(plan.mode, LocalDatabaseOpenMode.encrypted);
    expect(plan.keyHex, _key);
    expect(plan.migrated, isFalse);
    expect(file.existsSync(), isFalse);
  });

  test('a plaintext file is migrated when the cipher succeeds', () async {
    writePlaintext();
    final cipher = _FakeCipher();

    final plan = await encryption(cipher: cipher).prepare(file);

    expect(plan.mode, LocalDatabaseOpenMode.encrypted);
    expect(plan.keyHex, _key);
    expect(plan.migrated, isTrue);
    expect(cipher.migrateCalls, 1);
  });

  test('a failed migration leaves the plaintext file and falls back', () async {
    writePlaintext();
    final cipher = _FakeCipher()..throwOnMigrate = true;
    final reporter = _FakeReporter();

    final plan = await encryption(cipher: cipher, reporter: reporter).prepare(file);

    expect(plan.mode, LocalDatabaseOpenMode.plaintextFallback);
    expect(plan.keyHex, isNull);
    expect(plan.migrated, isFalse);
    expect(file.existsSync(), isTrue);
    expect(await isPlaintextDatabase(file), isTrue);
    expect(reporter.errors, hasLength(1));
  });

  test('an encrypted file with a valid key stays encrypted', () async {
    writeEncrypted();
    final cipher = _FakeCipher()..verifyResult = true;

    final plan = await encryption(cipher: cipher).prepare(file);

    expect(plan.mode, LocalDatabaseOpenMode.encrypted);
    expect(plan.keyHex, _key);
    expect(plan.migrated, isFalse);
    expect(cipher.verifyCalls, 1);
    expect(file.existsSync(), isTrue);
  });

  test('an encrypted file with an invalid key is deleted and recreated', () async {
    writeEncrypted();
    final cipher = _FakeCipher()..verifyResult = false;
    final reporter = _FakeReporter();

    final plan = await encryption(cipher: cipher, reporter: reporter).prepare(file);

    expect(plan.mode, LocalDatabaseOpenMode.encrypted);
    expect(plan.keyHex, _key);
    expect(file.existsSync(), isFalse);
    expect(reporter.errors, hasLength(1));
  });

  test('a key-store failure on a plaintext file falls back to plaintext', () async {
    writePlaintext();

    final plan = await encryption(keyStore: _FakeKeyStore(throwOnLoad: true)).prepare(file);

    expect(plan.mode, LocalDatabaseOpenMode.plaintextFallback);
    expect(plan.keyHex, isNull);
    expect(file.existsSync(), isTrue);
  });

  test('a key-store failure on an encrypted file throws', () async {
    writeEncrypted();

    await expectLater(
      encryption(keyStore: _FakeKeyStore(throwOnLoad: true)).prepare(file),
      throwsA(isA<StateError>()),
    );
  });

  test('isPlaintextDatabase recognises the SQLite header only', () async {
    writePlaintext();
    expect(await isPlaintextDatabase(file), isTrue);

    writeEncrypted();
    expect(await isPlaintextDatabase(file), isFalse);
  });

  test('a plaintext file falls back when SQLCipher is unavailable', () async {
    writePlaintext();
    final reporter = _FakeReporter();

    final plan = await encryption(
      cipher: _FakeCipher()..available = false,
      reporter: reporter,
    ).prepare(file);

    expect(plan.mode, LocalDatabaseOpenMode.plaintextFallback);
    expect(plan.keyHex, isNull);
    expect(reporter.errors, isNotEmpty);
  });

  test('an encrypted file throws when SQLCipher is unavailable', () async {
    writeEncrypted();

    await expectLater(
      encryption(cipher: _FakeCipher()..available = false).prepare(file),
      throwsA(isA<StateError>()),
    );
  });
}
