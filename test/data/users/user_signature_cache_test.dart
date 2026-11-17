// dart format width=100
//
// The saved technician signature, offline.
//
// Every rapportino pre-filled its "Firma tecnico" block from `/api/users/me/signature/content`,
// which with no signal simply answered nothing — so the one case the saved signature exists for
// (writing a rapportino on site) was the one case it never helped. These tests pin the local copy
// and the freshness rule that chooses between it and the server.

import 'dart:io';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tasktap_mobile/data/users/user_signature_api_client.dart';
import 'package:tasktap_mobile/data/users/user_signature_cache.dart';

class _FakeApi extends UserSignatureApiClient {
  _FakeApi({this.bytes}) : super(Dio());

  final Uint8List? bytes;
  int fetches = 0;

  @override
  Future<Uint8List?> fetchSavedSignatureContent() async {
    fetches++;
    return bytes;
  }
}

Uint8List _png(int seed) => Uint8List.fromList([137, 80, 78, 71, seed]);

void main() {
  late Directory root;
  late UserSignatureCache cache;

  setUp(() async {
    root = await Directory.systemTemp.createTemp('signature_cache_test');
    cache = UserSignatureCache(rootLoader: () async => root);
  });

  tearDown(() async {
    if (await root.exists()) await root.delete(recursive: true);
  });

  group('UserSignatureCache', () {
    test('round-trips the bytes, per user', () async {
      await cache.write('user-1', _png(1));
      await cache.write('user-2', _png(2));

      expect(await cache.read('user-1'), _png(1));
      expect(await cache.read('user-2'), _png(2));
    });

    // A signature is authorship. Several technicians sign in on the same phone, and a shared slot
    // would pre-fill one of them with another's signature.
    test('a user with no cached signature gets null, never the other user\'s', () async {
      await cache.write('user-1', _png(1));

      expect(await cache.read('user-2'), isNull);
    });

    test('an empty file is a miss, not an empty signature', () async {
      final dir = Directory('${root.path}/signatures');
      await dir.create(recursive: true);
      await File('${dir.path}/user-1.png').writeAsBytes(const []);

      expect(await cache.read('user-1'), isNull);
    });

    test('an id that is not a single path segment cannot escape the folder', () async {
      await cache.write('../escape', _png(1));

      expect(await cache.read('../escape'), _png(1));
      expect(File('${root.path}/escape.png').existsSync(), isFalse);
    });
  });

  group('signatureToPrefill', () {
    test('offline answers from the cache and never touches the network', () async {
      await cache.write('user-1', _png(7));
      final api = _FakeApi(bytes: _png(9));

      final bytes = await signatureToPrefill(
        online: false,
        userId: 'user-1',
        api: api,
        cache: cache,
      );

      expect(bytes, _png(7));
      expect(api.fetches, 0);
    });

    test('offline with nothing cached answers null', () async {
      final api = _FakeApi(bytes: _png(9));

      final bytes = await signatureToPrefill(
        online: false,
        userId: 'user-1',
        api: api,
        cache: cache,
      );

      expect(bytes, isNull);
      expect(api.fetches, 0);
    });

    // Before the first entitlement refresh the device does not know which technician is signed in,
    // so it has no cache key — and must not guess one.
    test('offline with no known user answers null and does not read anything else', () async {
      await cache.write('user-1', _png(7));

      expect(
        await signatureToPrefill(
          online: false,
          userId: null,
          api: _FakeApi(),
          cache: cache,
        ),
        isNull,
      );
    });

    test('online the server is the answer, and a successful fetch refreshes the cache', () async {
      await cache.write('user-1', _png(7));
      final api = _FakeApi(bytes: _png(9));

      final bytes = await signatureToPrefill(
        online: true,
        userId: 'user-1',
        api: api,
        cache: cache,
      );

      expect(bytes, _png(9));
      expect(api.fetches, 1);
      expect(await cache.read('user-1'), _png(9));
    });

    // A 404 means "you have no saved signature": the technician must draw one. A copy left over
    // from before a server-side delete must not quietly outvote that.
    test('online a missing server copy answers null even with a cached one', () async {
      await cache.write('user-1', _png(7));
      final api = _FakeApi(bytes: null);

      final bytes = await signatureToPrefill(
        online: true,
        userId: 'user-1',
        api: api,
        cache: cache,
      );

      expect(bytes, isNull);
      // The cached copy is left alone: it is the offline answer, and the next successful fetch
      // overwrites it.
      expect(await cache.read('user-1'), _png(7));
    });
  });
}
