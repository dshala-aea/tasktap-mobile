// dart format width=100
// Tests for `locationGeocodedLocationProvider` (lib/presentation/providers/schedule_providers.dart)
// — the Locations-table analog of `cantiereGeocodedLocationProvider`
// (test/features/cantiere/cantiere_providers_test.dart's own group covers that one).
//
// Uses an in-memory Drift DB — no network, no file system.
// Verifies the same cache-then-geocode-then-persist contract, against `Locations` instead of
// `Cantieri`:
//   - returns the cached point without geocoding, when already set
//   - geocodes the joined address and persists the result when not cached
//   - returns null without calling the geocoder when the location has no address
//   - returns null and writes nothing when the geocoder finds no match
//   - returns null when the location is not synced locally

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tasktap_mobile/core/location/geocoding_service.dart';
import 'package:tasktap_mobile/data/local/app_database.dart';
import 'package:tasktap_mobile/data/sync/sync_service.dart';
import 'package:tasktap_mobile/presentation/providers/schedule_providers.dart';

/// Records every address it was asked to geocode, and returns [pointToReturn] (default: a fixed
/// point) — or null when set, to exercise the "geocode failed" path without a real network call.
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
  late _FakeGeocodingService fakeGeocoder;
  late ProviderContainer container;

  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
    fakeGeocoder = _FakeGeocodingService();
    container = ProviderContainer(
      overrides: [
        appDatabaseProvider.overrideWithValue(db),
        geocodingServiceProvider.overrideWithValue(fakeGeocoder),
      ],
    );
  });

  tearDown(() async {
    container.dispose();
    await db.close();
  });

  group('locationGeocodedLocationProvider', () {
    test('returns the cached point without geocoding, when already set', () async {
      await db
          .into(db.locations)
          .insert(
            LocationsCompanion.insert(
              id: 'l-cached',
              tenantId: 'tenant1',
              createdAt: DateTime.utc(2026, 8, 31),
              customerId: 'cust-1',
              name: 'Sede cache',
              address: const Value('Via Cache 1'),
              latitude: const Value(41.9),
              longitude: const Value(12.5),
            ),
          );

      final result = await container.read(locationGeocodedLocationProvider('l-cached').future);

      expect(result, (lat: 41.9, lng: 12.5));
      expect(fakeGeocoder.geocodedAddresses, isEmpty);
    });

    test('geocodes the joined address and persists the result when not cached', () async {
      await db
          .into(db.locations)
          .insert(
            LocationsCompanion.insert(
              id: 'l-new',
              tenantId: 'tenant1',
              createdAt: DateTime.utc(2026, 8, 31),
              customerId: 'cust-1',
              name: 'Sede nuova',
              address: const Value('Via Roma 1'),
              city: const Value('Milano'),
              postalCode: const Value('20100'),
            ),
          );
      fakeGeocoder.pointToReturn = (lat: 45.4642, lng: 9.19);

      final result = await container.read(locationGeocodedLocationProvider('l-new').future);

      expect(result, (lat: 45.4642, lng: 9.19));
      expect(fakeGeocoder.geocodedAddresses, ['Via Roma 1, Milano, 20100']);

      final row = await (db.select(db.locations)..where((l) => l.id.equals('l-new'))).getSingle();
      expect(row.latitude, 45.4642);
      expect(row.longitude, 9.19);
    });

    test('returns null without calling the geocoder when the location has no address', () async {
      await db
          .into(db.locations)
          .insert(
            LocationsCompanion.insert(
              id: 'l-no-address',
              tenantId: 'tenant1',
              createdAt: DateTime.utc(2026, 8, 31),
              customerId: 'cust-1',
              name: 'Sede senza indirizzo',
            ),
          );

      final result = await container.read(locationGeocodedLocationProvider('l-no-address').future);

      expect(result, isNull);
      expect(fakeGeocoder.geocodedAddresses, isEmpty);
    });

    test('returns null and writes nothing when the geocoder finds no match', () async {
      await db
          .into(db.locations)
          .insert(
            LocationsCompanion.insert(
              id: 'l-unresolvable',
              tenantId: 'tenant1',
              createdAt: DateTime.utc(2026, 8, 31),
              customerId: 'cust-1',
              name: 'Sede irrisolvibile',
              address: const Value('Indirizzo inesistente'),
            ),
          );
      fakeGeocoder.pointToReturn = null;

      final result = await container.read(locationGeocodedLocationProvider('l-unresolvable').future);

      expect(result, isNull);
      final row = await (db.select(
        db.locations,
      )..where((l) => l.id.equals('l-unresolvable'))).getSingle();
      expect(row.latitude, isNull);
      expect(row.longitude, isNull);
    });

    test('returns null when the location is not synced locally', () async {
      final result = await container.read(locationGeocodedLocationProvider('missing').future);

      expect(result, isNull);
      expect(fakeGeocoder.geocodedAddresses, isEmpty);
    });
  });
}
