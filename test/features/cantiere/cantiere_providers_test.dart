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
import 'package:tasktap_mobile/data/local/app_database.dart';
import 'package:tasktap_mobile/data/sync/sync_service.dart';
import 'package:tasktap_mobile/features/cantiere/cantiere_providers.dart';

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
}
