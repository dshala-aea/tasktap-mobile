// test/data/local/local_database_key_store_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:tasktap_mobile/data/local/local_database_key_store.dart';

class _FakeStore implements SecureStringStore {
  final values = <String, String>{};

  @override
  Future<String?> read(String key) async => values[key];

  @override
  Future<void> write(String key, String value) async {
    values[key] = value;
  }
}

void main() {
  test('generates a 64-char lowercase hex key and persists it', () async {
    final storage = _FakeStore();
    final key = await SecureLocalDatabaseKeyStore(storage).loadOrCreate();

    expect(key, matches(RegExp(r'^[0-9a-f]{64}$')));
    expect(storage.values[SecureLocalDatabaseKeyStore.keyName], key);
  });

  test('reuses an existing key', () async {
    final storage = _FakeStore()
      ..values[SecureLocalDatabaseKeyStore.keyName] = 'a' * 64;

    expect(await SecureLocalDatabaseKeyStore(storage).loadOrCreate(), 'a' * 64);
  });

  test('replaces a malformed stored key', () async {
    final storage = _FakeStore()
      ..values[SecureLocalDatabaseKeyStore.keyName] = 'short';
    final key = await SecureLocalDatabaseKeyStore(storage).loadOrCreate();

    expect(key, matches(RegExp(r'^[0-9a-f]{64}$')));
    expect(storage.values[SecureLocalDatabaseKeyStore.keyName], key);
  });
}
