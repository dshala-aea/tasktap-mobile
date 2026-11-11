// dart format width=100
import 'dart:math';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// The slice of secure storage the DB key needs. An interface so key rotation/persistence can be
/// tested without a Keystore/Keychain.
abstract interface class SecureStringStore {
  Future<String?> read(String key);
  Future<void> write(String key, String value);
}

class FlutterSecureStringStore implements SecureStringStore {
  const FlutterSecureStringStore([this._storage = const FlutterSecureStorage()]);

  final FlutterSecureStorage _storage;

  @override
  Future<String?> read(String key) => _storage.read(key: key);

  @override
  Future<void> write(String key, String value) => _storage.write(key: key, value: value);
}

abstract interface class LocalDatabaseKeyStore {
  /// The raw SQLCipher key as 64 lowercase hex chars (32 bytes).
  Future<String> loadOrCreate();
}

/// One key per installation, held in the platform keystore alongside the auth tokens.
///
/// `Random.secure()` is deliberate: this key is the only thing between a copied `tasktap.db` and
/// the offline reports inside it.
class SecureLocalDatabaseKeyStore implements LocalDatabaseKeyStore {
  SecureLocalDatabaseKeyStore([SecureStringStore? store])
    : _store = store ?? const FlutterSecureStringStore();

  static const String keyName = 'tasktap.local_db_key.v1';

  static final _hexKey = RegExp(r'^[0-9a-f]{64}$');

  final SecureStringStore _store;

  @override
  Future<String> loadOrCreate() async {
    final existing = await _store.read(keyName);
    if (existing != null && _hexKey.hasMatch(existing)) return existing;

    final key = List<int>.generate(32, (_) => Random.secure().nextInt(256))
        .map((b) => b.toRadixString(16).padLeft(2, '0'))
        .join();
    await _store.write(keyName, key);
    return key;
  }
}
