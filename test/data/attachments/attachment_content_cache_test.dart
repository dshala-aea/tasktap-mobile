import 'dart:io';

import 'package:dio/dio.dart';
import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:tasktap_mobile/data/attachments/attachment_content_cache.dart';
import 'package:tasktap_mobile/data/local/app_database.dart';
import 'package:tasktap_mobile/data/sync/connectivity_provider.dart';

/// O-8c: the byte cache that makes a server-held photo, signature or PDF openable offline.
///
/// Sync mirrors attachment metadata, never the bytes, so everything here is about the third thing
/// the vision needs — the bytes themselves — staying on the phone: keyed so a replaced file can
/// never be served as the new one, capped so the cache cannot eat the device, and filled by a
/// sweep that only runs on unmetered Wi-Fi.
class MockDio extends Mock implements Dio {}

Response<List<int>> _bytes(List<int> body) =>
    Response(data: body, statusCode: 200, requestOptions: RequestOptions(path: '/x'));

void main() {
  late MockDio dio;
  late Directory root;

  setUp(() async {
    dio = MockDio();
    root = await Directory.systemTemp.createTemp('tt-attachment-cache-test');
  });

  tearDown(() async {
    if (await root.exists()) await root.delete(recursive: true);
  });

  void respondWith(List<int> body) {
    when(
      () => dio.get<List<int>>(any(), options: any(named: 'options')),
    ).thenAnswer((_) async => _bytes(body));
  }

  AttachmentContentCache cache({int maxBytes = 500 * 1024 * 1024}) =>
      AttachmentContentCache(dio: dio, maxBytes: maxBytes, rootLoader: () async => root);

  AttachmentRef ref({
    String id = 'a-1',
    String? hash = 'h1',
    int size = 3,
    String url = '/api/reports/r-1/attachments/a-1/content',
  }) => (allegatoId: id, contentHash: hash, sizeBytes: size, url: url);

  test('ensure downloads the bytes and lookup finds them afterwards', () async {
    respondWith([1, 2, 3]);
    final c = cache();

    final file = await c.ensure(ref());

    expect(file.existsSync(), isTrue);
    expect(await file.readAsBytes(), [1, 2, 3]);
    expect((await c.lookup(allegatoId: 'a-1', contentHash: 'h1', sizeBytes: 3))?.path, file.path);
  });

  test('a cache miss is null and touches the network not at all', () async {
    final hit = await cache().lookup(allegatoId: 'a-1', contentHash: 'h1', sizeBytes: 3);

    expect(hit, isNull);
    verifyNever(() => dio.get<List<int>>(any(), options: any(named: 'options')));
  });

  test('ensure serves the cached file without a second request', () async {
    respondWith([1, 2, 3]);
    final c = cache();
    await c.ensure(ref());

    await c.ensure(ref());

    verify(() => dio.get<List<int>>(any(), options: any(named: 'options'))).called(1);
  });

  test('a replaced allegato is a different key, and the old bytes are deleted', () async {
    respondWith([1, 2, 3]);
    final c = cache();
    final old = await c.ensure(ref(hash: 'h1'));

    respondWith([4, 5, 6]);
    final fresh = await c.ensure(ref(hash: 'h2'));

    expect(fresh.path, isNot(old.path));
    expect(await fresh.readAsBytes(), [4, 5, 6]);
    expect(
      old.existsSync(),
      isFalse,
      reason: 'one file per id: the unreachable old key must not linger',
    );
  });

  test('with no hash the key falls back to the size', () async {
    respondWith([1, 2, 3, 4]);
    final c = cache();

    final file = await c.ensure(ref(hash: null, size: 4));

    expect(file.path, endsWith('a-1__size-4'));
    expect((await c.lookup(allegatoId: 'a-1', sizeBytes: 4))?.path, file.path);
  });

  test('a failed download writes nothing', () async {
    when(
      () => dio.get<List<int>>(any(), options: any(named: 'options')),
    ).thenThrow(DioException(requestOptions: RequestOptions(path: '/x')));

    await expectLater(cache().ensure(ref()), throwsA(isA<DioException>()));

    expect(await root.list().toList(), isEmpty);
  });

  test('an empty body is not cached as an empty file', () async {
    respondWith(const []);

    await expectLater(cache().ensure(ref()), throwsA(isA<StateError>()));

    expect(await root.list().toList(), isEmpty);
  });

  test('eviction deletes the least recently used first', () async {
    var call = 0;
    void respond(int howMany) {
      call++;
      respondWith(List.filled(howMany, call));
    }

    final c = cache(maxBytes: 10);
    respond(4);
    final first = await c.ensure(ref(id: 'a-1', hash: 'h1', size: 4));

    // Explicit mtimes: the order must not depend on filesystem timestamp granularity.
    await first.setLastModified(DateTime(2026, 1, 1));
    respond(4);
    final second = await c.ensure(ref(id: 'a-2', hash: 'h2', size: 4));
    await second.setLastModified(DateTime(2026, 1, 2));

    respond(4);
    await c.ensure(ref(id: 'a-3', hash: 'h3', size: 4));

    expect(first.existsSync(), isFalse, reason: '8+4 > 10: the oldest goes');
    expect(second.existsSync(), isTrue);
    expect(await c.totalBytes(), lessThanOrEqualTo(10));
  });

  test('a lookup marks the file as used, a prefetch check does not', () async {
    respondWith([1, 2, 3]);
    final c = cache();
    final file = await c.ensure(ref());
    await file.setLastModified(DateTime(2026, 1, 1));

    await c.lookup(allegatoId: 'a-1', contentHash: 'h1', sizeBytes: 3, touch: false);
    expect((await file.stat()).modified.isAtSameMomentAs(DateTime(2026, 1, 1)), isTrue);

    await c.lookup(allegatoId: 'a-1', contentHash: 'h1', sizeBytes: 3);
    expect((await file.stat()).modified.isAfter(DateTime(2026, 1, 1)), isTrue);
  });

  group('AttachmentPrefetcher', () {
    late AppDatabase db;

    setUp(() {
      driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
      db = AppDatabase(NativeDatabase.memory());
    });

    tearDown(() => db.close());

    Future<void> seedServerFile(String id, {int entityType = 1, String? hash = 'h1'}) => db
        .into(db.reportAllegati)
        .insert(
          ReportAllegatiCompanion.insert(
            id: id,
            tenantId: 't',
            createdAt: DateTime.utc(2026, 10, 20),
            fileName: '$id.jpg',
            contentType: 'image/jpeg',
            sizeBytes: 3,
            storagePath: '',
            url: '/api/reports/r/attachments/x/content',
            entityType: entityType,
            entityId: entityType == 0 ? 'ticket-1' : 'r-1',
            uploadedByUserId: 'u',
            contentHash: Value(hash),
          ),
        );

    test('a ticket file is cached under the key the ticket tab reads it with', () async {
      respondWith([1, 2, 3]);
      final c = cache();
      await seedServerFile('a-9', entityType: 0);

      await AttachmentPrefetcher(db: db, cache: c, canPrefetch: () async => true).run();

      // The ticket Allegati tab holds no hash (its DTO never carries one), so it asks by size.
      expect(
        await c.lookup(allegatoId: 'a-9', contentHash: 'h1', sizeBytes: 3, touch: false),
        isNull,
        reason: 'a hash key nothing looks up would be dead weight in the cache',
      );
      expect(
        (await c.lookup(allegatoId: 'a-9', sizeBytes: 3, touch: false))?.existsSync(),
        isTrue,
      );
    });

    test('does nothing at all off Wi-Fi', () async {
      await seedServerFile('a-1');

      final fetched = await AttachmentPrefetcher(
        db: db,
        cache: cache(),
        canPrefetch: () async => false,
      ).run();

      expect(fetched, 0);
      verifyNever(() => dio.get<List<int>>(any(), options: any(named: 'options')));
    });

    test('downloads what is missing and skips what is cached', () async {
      respondWith([1, 2, 3]);
      final c = cache();
      await seedServerFile('a-1');
      await seedServerFile('a-2');
      await c.ensure(
        ref(id: 'a-1', url: '/api/reports/r/attachments/x/content'),
      );

      final fetched = await AttachmentPrefetcher(
        db: db,
        cache: c,
        canPrefetch: () async => true,
      ).run();

      expect(fetched, 1);
      expect(
        (await c.lookup(allegatoId: 'a-2', contentHash: 'h1', sizeBytes: 3))?.existsSync(),
        isTrue,
      );
    });

    test('stops at the cache cap instead of thrashing', () async {
      respondWith([1, 2, 3]);
      final c = cache(maxBytes: 3);
      await seedServerFile('a-1');
      await seedServerFile('a-2');
      await c.ensure(
        ref(id: 'a-1', url: '/api/reports/r/attachments/x/content'),
      );

      final fetched = await AttachmentPrefetcher(
        db: db,
        cache: c,
        canPrefetch: () async => true,
      ).run();

      expect(fetched, 0, reason: 'already full: nothing more is downloaded');
    });

    test('stops on a network error and leaves the rest for the next sync', () async {
      when(
        () => dio.get<List<int>>(any(), options: any(named: 'options')),
      ).thenThrow(DioException(requestOptions: RequestOptions(path: '/x')));
      await seedServerFile('a-1');
      await seedServerFile('a-2');

      final fetched = await AttachmentPrefetcher(
        db: db,
        cache: cache(),
        canPrefetch: () async => true,
      ).run();

      expect(fetched, 0);
      verify(() => dio.get<List<int>>(any(), options: any(named: 'options'))).called(1);
    });
  });

  group('attachmentFileProvider', () {
    test('offline and cold it answers null instead of an error', () async {
      final container = ProviderContainer(
        overrides: [
          attachmentContentCacheProvider.overrideWithValue(cache()),
          isOnlineProvider.overrideWithValue(false),
        ],
      );
      addTearDown(container.dispose);

      final file = await container.read(attachmentFileProvider(ref()).future);

      expect(file, isNull);
      verifyNever(() => dio.get<List<int>>(any(), options: any(named: 'options')));
    });

    test('online and cold it fetches', () async {
      respondWith([1, 2, 3]);
      final container = ProviderContainer(
        overrides: [
          attachmentContentCacheProvider.overrideWithValue(cache()),
          isOnlineProvider.overrideWithValue(true),
        ],
      );
      addTearDown(container.dispose);

      final file = await container.read(attachmentFileProvider(ref()).future);

      expect(file, isNotNull);
      expect(await file!.readAsBytes(), [1, 2, 3]);
    });
  });
}
