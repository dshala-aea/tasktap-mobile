// dart format width=100
// test/features/admin/locations/admin_location_detail_screen_test.dart
//
// Widget tests for AdminLocationDetailScreen ("sede" detail, admin/office-facing).
//
// Covers:
//   - renders the location's KeyVal fields (Nome, Città, Indirizzo, CAP, Telefono, Note)
//   - shows the "not synced" unavailable state when the location isn't in the local mirror
//   - shows GeoMapCard (never a raw "Coordinate: lat, lng" row) when the location has an address
//   - shows no map section when the location has no address at all
//   - never renders the location's raw latitude/longitude as bare numeric text anywhere on screen

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tasktap_mobile/core/location/geocoding_service.dart';
import 'package:tasktap_mobile/core/widgets/app_map_card.dart';
import 'package:tasktap_mobile/core/widgets/geo_map_card.dart';
import 'package:tasktap_mobile/data/local/app_database.dart';
import 'package:tasktap_mobile/data/sync/sync_service.dart';
import 'package:tasktap_mobile/features/admin/locations/admin_location_detail_screen.dart';

/// Never geocodes for real — every test in this file overrides `geocodingServiceProvider` with
/// this, so a location with an address exercises `GeoMapCard`'s fallback path (`AppMapCard`,
/// unchanged) deterministically instead of racing a real Nominatim request. Mirrors
/// `test/features/cantiere/cantiere_detail_screen_test.dart`'s own `_NullGeocodingService`.
class _NullGeocodingService extends GeocodingService {
  _NullGeocodingService() : super(dio: null);

  @override
  Future<GeocodedPoint?> geocode(String address) async => null;
}

Widget _buildDetail({required AppDatabase db, String locationId = 'loc-1'}) {
  return ProviderScope(
    overrides: [
      appDatabaseProvider.overrideWithValue(db),
      geocodingServiceProvider.overrideWithValue(_NullGeocodingService()),
    ],
    child: MaterialApp(home: AdminLocationDetailScreen(locationId: locationId)),
  );
}

void main() {
  setUpAll(() {
    driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  });

  late AppDatabase db;
  setUp(() => db = AppDatabase(NativeDatabase.memory()));
  tearDown(() async => db.close());

  Future<void> seedLocation({
    String id = 'loc-1',
    String name = 'Sede Milano',
    String? address,
    String? city,
    String? postalCode,
    String? phone,
    String? notes,
    double? latitude,
    double? longitude,
  }) async {
    await db
        .into(db.customers)
        .insert(
          CustomersCompanion.insert(
            id: 'cust-1',
            tenantId: 'tenant-1',
            createdAt: DateTime.utc(2026, 1, 1),
            companyName: 'ACME Srl',
          ),
        );
    await db
        .into(db.locations)
        .insert(
          LocationsCompanion.insert(
            id: id,
            tenantId: 'tenant-1',
            createdAt: DateTime.utc(2026, 1, 1),
            customerId: 'cust-1',
            name: name,
            address: Value(address),
            city: Value(city),
            postalCode: Value(postalCode),
            phone: Value(phone),
            notes: Value(notes),
            latitude: Value(latitude),
            longitude: Value(longitude),
          ),
        );
  }

  // CRITICAL: this screen watches `adminLocationDetailProvider`/`locationGeocodedLocationProvider`
  // (a Drift stream + a FutureProvider reading the same DB), so every test below ends by
  // explicitly unmounting the widget tree — otherwise Drift's StreamQueryStore leaves a pending
  // Timer behind and the test framework fails with "A Timer is still pending". Mirrors the
  // documented convention in admin_location_form_screen_test.dart / admin_cantiere_detail_screen_test.dart.
  Future<void> unmount(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
  }

  testWidgets('renders KeyVal fields for a synced location', (tester) async {
    await seedLocation(
      address: 'Via Roma 1',
      city: 'Milano',
      postalCode: '20100',
      phone: '02 1234567',
      notes: 'Portone sul retro',
    );

    await tester.pumpWidget(_buildDetail(db: db));
    await tester.pumpAndSettle();

    expect(find.text('Sede Milano'), findsWidgets);
    expect(find.text('Milano'), findsWidgets);
    expect(find.text('Via Roma 1'), findsWidgets);
    expect(find.text('20100'), findsOneWidget);
    expect(find.text('02 1234567'), findsOneWidget);
    expect(find.text('Portone sul retro'), findsOneWidget);

    await unmount(tester);
  });

  testWidgets('shows the unavailable state when the location is not synced locally', (
    tester,
  ) async {
    await tester.pumpWidget(_buildDetail(db: db, locationId: 'missing'));
    await tester.pumpAndSettle();

    expect(find.text('Sede non disponibile'), findsOneWidget);

    await unmount(tester);
  });

  testWidgets(
    'shows GeoMapCard, never a raw "Coordinate" row, when the location already has lat/lng',
    (tester) async {
      await seedLocation(address: 'Via Roma 1', city: 'Milano', latitude: 45.4642, longitude: 9.19);

      await tester.pumpWidget(_buildDetail(db: db));
      // Bounded pumps, not pumpAndSettle: the cached lat/lng resolves with no real geocoding call,
      // so GeoMapCard mounts the real (offline, tile-less-in-tests) embedded map — its TileLayer's
      // network image requests never "settle" the way pumpAndSettle waits for, the same reason
      // ticket_detail_screen_test.dart's own `pump()` helper uses bounded pumps for its live-timer
      // cases. The assertions below only need the widget tree built, not tiles painted.
      for (var i = 0; i < 6; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }

      expect(find.byType(GeoMapCard), findsOneWidget);
      expect(find.text('Coordinate'), findsNothing);
      // The old raw rendering would have shown this exact string — assert it's gone entirely.
      expect(find.text('45.4642, 9.19'), findsNothing);

      await unmount(tester);
    },
  );

  testWidgets(
    'shows GeoMapCard (falling back to AppMapCard) when the location has an address but no cached lat/lng',
    (tester) async {
      await seedLocation(address: 'Via Torino 5', city: 'Torino');

      await tester.pumpWidget(_buildDetail(db: db));
      await tester.pumpAndSettle();

      expect(find.byType(GeoMapCard), findsOneWidget);
      // The fake geocoder never resolves a point, so this exercises GeoMapCard's own fallback.
      expect(find.byType(AppMapCard), findsOneWidget);
      expect(find.text('Via Torino 5, Torino'), findsOneWidget);

      await unmount(tester);
    },
  );

  testWidgets('shows no map section when the location has no address at all', (tester) async {
    await seedLocation(name: 'Sede senza indirizzo');

    await tester.pumpWidget(_buildDetail(db: db));
    await tester.pumpAndSettle();

    expect(find.byType(GeoMapCard), findsNothing);

    await unmount(tester);
  });
}
