// Tests for the Cantieri tab's read-only providers.
//
// Uses an in-memory Drift DB — no network, no file system.
// Verifies:
//   - cantiereByIdProvider: returns the matching cantiere, or null when none matches
//   - ticketsForCantiereProvider: returns only tickets whose cantiereId matches
//   - cantiereGeocodedLocationProvider: cache-then-geocode-then-persist, never re-geocoding a
//     cantiere that's already cached (see the group's own header comment)

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tasktap_mobile/core/location/geocoding_service.dart';
import 'package:tasktap_mobile/core/time/business_time.dart';
import 'package:tasktap_mobile/core/time/business_time_providers.dart' show businessTimeProvider;
import 'package:tasktap_mobile/data/local/app_database.dart';
import 'package:tasktap_mobile/data/sync/connectivity_provider.dart' show isOnlineProvider;
import 'package:tasktap_mobile/data/sync/sync_service.dart';
import 'package:tasktap_mobile/features/cantiere/cantiere_providers.dart';
import 'package:tasktap_mobile/presentation/providers/auth_providers.dart'
    show internalUserIdProvider;

/// Records every address it was asked to geocode, and returns [pointToReturn] (default: a fixed
/// point) — or null when [failNextLookup] is set, to exercise the "geocode failed" path without a
/// real network call.
class _FakeGeocodingService extends GeocodingService {
  _FakeGeocodingService() : super(dio: null);

  final List<String> geocodedAddresses = [];
  GeocodedPoint? pointToReturn = (lat: 45.0, lng: 9.0);

  @override
  Future<GeocodedPoint?> geocode(String address) async {
    geocodedAddresses.add(address);
    return pointToReturn;
  }
}

void main() {
  late AppDatabase db;
  late ProviderContainer container;

  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
    container = ProviderContainer(
      overrides: [appDatabaseProvider.overrideWithValue(db)],
    );
  });

  tearDown(() async {
    container.dispose();
    await db.close();
  });

  group('cantiereByIdProvider', () {
    test('returns the matching cantiere', () async {
      await db
          .into(db.cantieri)
          .insert(
            CantieriCompanion.insert(
              id: 'c1',
              tenantId: 'tenant1',
              createdAt: DateTime.utc(2026, 8, 31),
              name: 'Cantiere Test',
            ),
          );

      final result = await container.read(cantiereByIdProvider('c1').future);

      expect(result?.name, 'Cantiere Test');
    });

    test('returns null when no cantiere matches', () async {
      final result = await container.read(
        cantiereByIdProvider('missing').future,
      );

      expect(result, isNull);
    });
  });

  group('ticketsForCantiereProvider', () {
    test('returns only tickets linked to that cantiere', () async {
      await db
          .into(db.tickets)
          .insert(
            TicketsCompanion.insert(
              id: 't1',
              tenantId: 'tenant1',
              createdAt: DateTime.utc(2026, 8, 31),
              title: 'Linked',
              customerId: 'c1',
              locationId: 'l1',
              statusId: 1,
              typeId: 1,
              cantiereId: const Value('cantiere-1'),
            ),
          );
      await db
          .into(db.tickets)
          .insert(
            TicketsCompanion.insert(
              id: 't2',
              tenantId: 'tenant1',
              createdAt: DateTime.utc(2026, 8, 31),
              title: 'Unlinked',
              customerId: 'c1',
              locationId: 'l1',
              statusId: 1,
              typeId: 1,
            ),
          );

      final result = await container.read(
        ticketsForCantiereProvider('cantiere-1').future,
      );

      expect(result.map((t) => t.id), ['t1']);
    });
  });

  group('cantiereGeocodedLocationProvider', () {
    late _FakeGeocodingService fakeGeocoder;
    late ProviderContainer geoContainer;

    setUp(() {
      fakeGeocoder = _FakeGeocodingService();
      geoContainer = ProviderContainer(
        overrides: [
          appDatabaseProvider.overrideWithValue(db),
          geocodingServiceProvider.overrideWithValue(fakeGeocoder),
        ],
      );
    });

    tearDown(() => geoContainer.dispose());

    test(
      'returns the cached point without geocoding, when already set',
      () async {
        await db
            .into(db.cantieri)
            .insert(
              CantieriCompanion.insert(
                id: 'c-cached',
                tenantId: 'tenant1',
                createdAt: DateTime.utc(2026, 8, 31),
                name: 'Cantiere cache',
                address: const Value('Via Cache 1'),
                latitude: const Value(41.9),
                longitude: const Value(12.5),
              ),
            );

        final result = await geoContainer.read(
          cantiereGeocodedLocationProvider('c-cached').future,
        );

        expect(result, (lat: 41.9, lng: 12.5));
        expect(fakeGeocoder.geocodedAddresses, isEmpty);
      },
    );

    test(
      'geocodes the joined address and persists the result when not cached',
      () async {
        await db
            .into(db.cantieri)
            .insert(
              CantieriCompanion.insert(
                id: 'c-new',
                tenantId: 'tenant1',
                createdAt: DateTime.utc(2026, 8, 31),
                name: 'Cantiere nuovo',
                address: const Value('Via Roma 1'),
                city: const Value('Milano'),
                postalCode: const Value('20100'),
              ),
            );
        fakeGeocoder.pointToReturn = (lat: 45.4642, lng: 9.19);

        final result = await geoContainer.read(
          cantiereGeocodedLocationProvider('c-new').future,
        );

        expect(result, (lat: 45.4642, lng: 9.19));
        expect(fakeGeocoder.geocodedAddresses, ['Via Roma 1, Milano, 20100']);

        final row = await (db.select(
          db.cantieri,
        )..where((c) => c.id.equals('c-new'))).getSingle();
        expect(row.latitude, 45.4642);
        expect(row.longitude, 9.19);
      },
    );

    test(
      'returns null without calling the geocoder when the cantiere has no address',
      () async {
        await db
            .into(db.cantieri)
            .insert(
              CantieriCompanion.insert(
                id: 'c-no-address',
                tenantId: 'tenant1',
                createdAt: DateTime.utc(2026, 8, 31),
                name: 'Cantiere senza indirizzo',
              ),
            );

        final result = await geoContainer.read(
          cantiereGeocodedLocationProvider('c-no-address').future,
        );

        expect(result, isNull);
        expect(fakeGeocoder.geocodedAddresses, isEmpty);
      },
    );

    test(
      'returns null and writes nothing when the geocoder finds no match',
      () async {
        await db
            .into(db.cantieri)
            .insert(
              CantieriCompanion.insert(
                id: 'c-unresolvable',
                tenantId: 'tenant1',
                createdAt: DateTime.utc(2026, 8, 31),
                name: 'Cantiere irrisolvibile',
                address: const Value('Indirizzo inesistente'),
              ),
            );
        fakeGeocoder.pointToReturn = null;

        final result = await geoContainer.read(
          cantiereGeocodedLocationProvider('c-unresolvable').future,
        );

        expect(result, isNull);
        final row = await (db.select(
          db.cantieri,
        )..where((c) => c.id.equals('c-unresolvable'))).getSingle();
        expect(row.latitude, isNull);
        expect(row.longitude, isNull);
      },
    );

    test('returns null when the cantiere is not synced locally', () async {
      final result = await geoContainer.read(
        cantiereGeocodedLocationProvider('missing').future,
      );

      expect(result, isNull);
      expect(fakeGeocoder.geocodedAddresses, isEmpty);
    });
  });

  group('offline site hours (cantiere_work_logs mirror)', () {
    late ProviderContainer offlineContainer;

    setUp(() {
      offlineContainer = ProviderContainer(
        overrides: [
          appDatabaseProvider.overrideWithValue(db),
          isOnlineProvider.overrideWithValue(false),
          internalUserIdProvider.overrideWith((ref) async => 'user-1'),
          // Pinned so the mirror's instants render as a fixed Rome wall clock — the same shape the
          // server sends, which is what lets the suggestion code not care where a row came from.
          businessTimeProvider.overrideWithValue(BusinessTime('Europe/Rome')),
        ],
      );
    });

    tearDown(() => offlineContainer.dispose());

    Future<void> insertMirrorRow({
      String id = 'w1',
      String cantiereId = 'site-1',
      String userId = 'user-1',
      DateTime? workDate,
      int startSeconds = 8 * 3600,
      int? endSeconds = 12 * 3600,
      DateTime? startUtc,
      DateTime? endUtc,
      String? clientId,
    }) => db
        .into(db.cantiereWorkLogs)
        .insert(
          CantiereWorkLogsCompanion.insert(
            id: id,
            cantiereId: cantiereId,
            userId: userId,
            workDate: workDate ?? DateTime.utc(2026, 10, 22),
            startSeconds: startSeconds,
            endSeconds: Value(endSeconds),
            startUtc: Value(startUtc),
            endUtc: Value(endUtc),
            approvalStatus: const Value(2),
            clientId: Value(clientId),
            createdAt: DateTime.utc(2026, 10, 22, 6),
          ),
        );

    test('the mirror provider returns one site\'s shifts, newest first', () async {
      await insertMirrorRow(id: 'w-old', workDate: DateTime.utc(2026, 10, 20));
      await insertMirrorRow(id: 'w-new', workDate: DateTime.utc(2026, 10, 22));
      await insertMirrorRow(id: 'w-other-site', cantiereId: 'site-2');

      final rows = await offlineContainer.read(
        cantiereWorkLogMirrorProvider('site-1').future,
      );

      expect(
        rows.map((r) => r.id),
        ['w-new', 'w-old'],
        reason: 'the detail screen lists the newest shift first',
      );
    });

    test('answers from the mirror while offline, shaped like the server DTO', () async {
      await insertMirrorRow(
        startUtc: DateTime.utc(2026, 10, 22, 6),
        endUtc: DateTime.utc(2026, 10, 22, 10, 30),
        clientId: 'device-key-1',
      );

      final logs = await offlineContainer.read(
        cantiereWorklogsProvider((userId: 'user-1', cantiereId: 'site-1')).future,
      );

      expect(logs, hasLength(1));
      expect(logs.single.workDate, DateTime.utc(2026, 10, 22));
      expect(
        logs.single.startTime,
        '08:00:00',
        reason: 'the true instant wins over the stored time-of-day',
      );
      expect(logs.single.endTime, '12:30:00');
      expect(logs.single.duration, const Duration(hours: 4, minutes: 30));
    });

    test('a shift only in the outbox is still readable, and a mirrored one is not doubled', () async {
      // One shift the server already knows (mirror), identified by the device key it was queued
      // under, and one still queued.
      await insertMirrorRow(id: 'w-known', clientId: 'punch-known');

      Future<void> punch(String id, String type, DateTime at) => db
          .into(db.cantierePunches)
          .insert(
            CantierePunchesCompanion.insert(
              id: id,
              eventTime: at,
              eventType: type,
              cantiereId: const Value('site-1'),
            ),
          );

      await punch('punch-known', 'ingresso', DateTime.utc(2026, 10, 21, 6));
      await punch('punch-known-out', 'uscita', DateTime.utc(2026, 10, 21, 10));
      await punch('punch-queued', 'ingresso', DateTime.utc(2026, 10, 23, 6));
      await punch('punch-queued-out', 'uscita', DateTime.utc(2026, 10, 23, 9));

      final logs = await offlineContainer.read(
        cantiereWorklogsProvider((userId: 'user-1', cantiereId: 'site-1')).future,
      );

      expect(
        logs.map((l) => l.id),
        unorderedEquals(['w-known', 'punch-queued']),
        reason: 'the synced shift is not counted twice, and the unsent one is not lost',
      );
      final queued = logs.firstWhere((l) => l.id == 'punch-queued');
      expect(queued.duration, const Duration(hours: 3));
    });

    test('a teammate\'s hours are not answered from this device', () async {
      await insertMirrorRow();

      final logs = await offlineContainer.read(
        cantiereWorklogsProvider((userId: 'user-2', cantiereId: 'site-1')).future,
      );

      expect(
        logs,
        isEmpty,
        reason: 'the device holds only its own punches; borrowing them would be a false answer',
      );
    });
  });
}
