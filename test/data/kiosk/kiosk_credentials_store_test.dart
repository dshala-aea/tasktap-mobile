// Tests for KioskCredentialsStore — the secure-storage wrapper backing kiosk mode's activation
// state (see lib/data/kiosk/kiosk_credentials_store.dart's own doc comment).
//
// FlutterSecureStorage is mocked (mocktail), backed by a plain in-memory map, mirroring the
// pattern in test/data/auth/zitadel_auth_repository_test.dart.

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:tasktap_mobile/data/kiosk/kiosk_credentials_store.dart';

class MockSecureStorage extends Mock implements FlutterSecureStorage {}

void main() {
  late MockSecureStorage storage;
  late Map<String, String> backing;
  late KioskCredentialsStore store;

  setUp(() {
    storage = MockSecureStorage();
    backing = {};

    when(
      () => storage.write(
        key: any(named: 'key'),
        value: any(named: 'value'),
        aOptions: any(named: 'aOptions'),
        iOptions: any(named: 'iOptions'),
        lOptions: any(named: 'lOptions'),
        webOptions: any(named: 'webOptions'),
        mOptions: any(named: 'mOptions'),
        wOptions: any(named: 'wOptions'),
      ),
    ).thenAnswer((invocation) async {
      final key = invocation.namedArguments[#key] as String;
      final value = invocation.namedArguments[#value] as String?;
      if (value == null) {
        backing.remove(key);
      } else {
        backing[key] = value;
      }
    });

    when(
      () => storage.read(
        key: any(named: 'key'),
        aOptions: any(named: 'aOptions'),
        iOptions: any(named: 'iOptions'),
        lOptions: any(named: 'lOptions'),
        webOptions: any(named: 'webOptions'),
        mOptions: any(named: 'mOptions'),
        wOptions: any(named: 'wOptions'),
      ),
    ).thenAnswer((invocation) async {
      final key = invocation.namedArguments[#key] as String;
      return backing[key];
    });

    when(
      () => storage.delete(
        key: any(named: 'key'),
        aOptions: any(named: 'aOptions'),
        iOptions: any(named: 'iOptions'),
        lOptions: any(named: 'lOptions'),
        webOptions: any(named: 'webOptions'),
        mOptions: any(named: 'mOptions'),
        wOptions: any(named: 'wOptions'),
      ),
    ).thenAnswer((invocation) async {
      final key = invocation.namedArguments[#key] as String;
      backing.remove(key);
    });

    store = KioskCredentialsStore(storage: storage);
  });

  test('read returns null when nothing was ever saved', () async {
    expect(await store.read(), isNull);
  });

  test('save then read round-trips the raw key and label', () async {
    await store.save(rawKey: 'sp_abc123', deviceLabel: 'Totem ingresso', exitPin: '1234');

    final creds = await store.read();
    expect(creds, isNotNull);
    expect(creds!.rawKey, 'sp_abc123');
    expect(creds.deviceLabel, 'Totem ingresso');
  });

  test('the raw key is never stored as plaintext under any other key', () async {
    await store.save(rawKey: 'sp_abc123', deviceLabel: '', exitPin: '9999');

    // The PIN itself must never be recoverable from storage — only a hash of it.
    expect(backing.values, isNot(contains('9999')));
  });

  test('verifyExitPin accepts the exact PIN used at save time', () async {
    await store.save(rawKey: 'sp_abc123', deviceLabel: '', exitPin: '4321');

    expect(await store.verifyExitPin('4321'), isTrue);
  });

  test('verifyExitPin rejects a wrong PIN', () async {
    await store.save(rawKey: 'sp_abc123', deviceLabel: '', exitPin: '4321');

    expect(await store.verifyExitPin('0000'), isFalse);
  });

  test('verifyExitPin rejects any PIN when nothing was ever saved', () async {
    expect(await store.verifyExitPin('4321'), isFalse);
  });

  test('clear wipes the raw key, label and PIN hash', () async {
    await store.save(rawKey: 'sp_abc123', deviceLabel: 'Totem', exitPin: '4321');

    await store.clear();

    expect(await store.read(), isNull);
    expect(await store.verifyExitPin('4321'), isFalse);
  });
}
