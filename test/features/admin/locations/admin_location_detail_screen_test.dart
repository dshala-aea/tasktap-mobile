// dart format width=100
// test/features/admin/locations/admin_location_detail_screen_test.dart
//
// Widget tests for AdminLocationDetailScreen ("sede" detail, admin/office-facing).
//
// Covers:
//   - summary hero + Modifica (gated on clienti.location.write)
//   - section order Documenti & mappa → Relazioni → Sintesi → Attività
//   - Relazioni from the local mirror (cliente, referenti, contratti)
//   - Sintesi facts (address, CAP, phone, notes) without repeating the hero's city
//   - Attività tickets from the local mirror
//   - empty sections hidden
//   - the "not synced" / "not found" unavailable states
//   - GeoMapCard (never a raw "Coordinate" row) when the location has an address
//   - no map section when the location has no address at all
//   - no raw latitude/longitude anywhere on screen

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tasktap_mobile/core/location/geocoding_service.dart';
import 'package:tasktap_mobile/core/widgets/app_map_card.dart';
import 'package:tasktap_mobile/core/widgets/geo_map_card.dart';
import 'package:tasktap_mobile/data/entitlements/entitlement_providers.dart';
import 'package:tasktap_mobile/data/entitlements/entitlement_repository.dart';
import 'package:tasktap_mobile/data/local/app_database.dart' hide Entitlement;
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

Entitlement _entitlement({bool canWrite = true}) => Entitlement(
  features: const {},
  capabilities: canWrite ? const {'clienti.location.write'} : const {},
  seatType: 'office',
  fetchedAt: DateTime.utc(2026, 9, 23),
);

Widget _buildDetail({required AppDatabase db, String locationId = 'loc-1', bool canWrite = true}) {
  return ProviderScope(
    overrides: [
      appDatabaseProvider.overrideWithValue(db),
      geocodingServiceProvider.overrideWithValue(_NullGeocodingService()),
      cachedEntitlementProvider.overrideWith(
        (ref) => Future.value(_entitlement(canWrite: canWrite)),
      ),
    ],
    child: MaterialApp(home: AdminLocationDetailScreen(locationId: locationId)),
  );
}

/// Pumps at a tall phone surface so every lazily-built section is on screen: the default 800×600
/// test window only builds the hero and the first section, leaving Relazioni/Sintesi/Attività
/// unbuilt and unfindable.
Future<void> _pumpDetail(
  WidgetTester tester, {
  required AppDatabase db,
  String locationId = 'loc-1',
  bool canWrite = true,
  bool settle = true,
}) async {
  await tester.binding.setSurfaceSize(const Size(390, 1800));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(_buildDetail(db: db, locationId: locationId, canWrite: canWrite));
  if (settle) await tester.pumpAndSettle();
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
    bool isActive = true,
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
            isActive: Value(isActive),
          ),
        );
  }

  Future<void> seedTicket({
    String id = 'ticket-1',
    required String locationId,
    String title = 'Perdita acqua sotto il lavello',
    DateTime? createdAt,
  }) async {
    await db
        .into(db.ticketStatuses)
        .insert(
          TicketStatusesCompanion.insert(id: const Value(1), tenantId: 'tenant-1', name: 'Aperto'),
        );
    await db
        .into(db.tickets)
        .insert(
          TicketsCompanion.insert(
            id: id,
            tenantId: 'tenant-1',
            createdAt: createdAt ?? DateTime.utc(2026, 11, 3),
            title: title,
            customerId: 'cust-1',
            locationId: locationId,
            statusId: 1,
            typeId: 1,
          ),
        );
  }

  Future<void> seedRelationData({String locationId = 'loc-1'}) async {
    await db
        .into(db.customerContacts)
        .insert(
          CustomerContactsCompanion.insert(
            id: 'contact-1',
            customerId: 'cust-1',
            name: 'Mario Bianchi',
            role: const Value('Responsabile acquisti'),
            phone: const Value('02 9876543'),
          ),
        );
    await db
        .into(db.contracts)
        .insert(
          ContractsCompanion.insert(
            id: 'contract-1',
            tenantId: 'tenant-1',
            createdAt: DateTime.utc(2026, 1, 1),
            name: 'Full service',
            customerId: 'cust-1',
            locationId: Value(locationId),
            startDate: DateTime.utc(2026, 1, 1),
            endDate: Value(DateTime.utc(2026, 12, 31)),
            isActive: const Value(true),
          ),
        );
  }

  // CRITICAL: this screen watches Drift streams, so every test below ends by explicitly
  // unmounting the widget tree — otherwise Drift's StreamQueryStore leaves a pending Timer behind
  // and the test framework fails with "A Timer is still pending".
  Future<void> unmount(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
  }

  testWidgets('renders the summary hero, Modifica and the four sections', (tester) async {
    await seedLocation(
      address: 'Via Roma 1',
      city: 'Milano',
      postalCode: '20100',
      phone: '02 1234567',
      notes: 'Portone sul retro',
    );
    await seedTicket(locationId: 'loc-1');

    await _pumpDetail(tester, db: db);

    // The collapsed bar is always built (slid offscreen), so hero assertions are scoped to the
    // hero card instead of matching its offscreen copy.
    final hero = find.byKey(const Key('detail-hero-card'));
    expect(find.text('Sede'), findsOneWidget); // app bar title
    expect(find.descendant(of: hero, matching: find.text('Sede Milano')), findsOneWidget);
    expect(find.descendant(of: hero, matching: find.text('ATTIVA')), findsOneWidget);
    expect(
      find.descendant(of: hero, matching: find.text('ACME Srl · Milano · 1 intervento')),
      findsOneWidget,
    );
    expect(find.descendant(of: hero, matching: find.text('Modifica')), findsOneWidget);

    expect(find.text('Documenti & mappa'), findsOneWidget);
    expect(find.text('Relazioni'), findsOneWidget);
    expect(find.text('Sintesi'), findsOneWidget);
    expect(find.text('Attività'), findsOneWidget);

    expect(find.text('Via Roma 1'), findsOneWidget);
    expect(find.text('20100'), findsOneWidget);
    expect(find.text('02 1234567'), findsOneWidget);
    expect(find.text('Portone sul retro'), findsOneWidget);

    await unmount(tester);
  });

  testWidgets('hides Modifica without the clienti.location.write capability', (tester) async {
    await seedLocation(address: 'Via Roma 1', city: 'Milano');

    await _pumpDetail(tester, db: db, canWrite: false);

    expect(find.text('Modifica'), findsNothing);

    await unmount(tester);
  });

  testWidgets('Relazioni lists cliente, referenti and contratti from the local mirror', (
    tester,
  ) async {
    await seedLocation(address: 'Via Roma 1', city: 'Milano');
    await seedRelationData();

    await _pumpDetail(tester, db: db);

    expect(find.text('Cliente'), findsOneWidget);
    expect(find.text('ACME SRL'), findsOneWidget);
    expect(find.text('Mario Bianchi'), findsOneWidget);
    expect(find.text('Full service'), findsOneWidget);
    expect(find.textContaining('31/12/2026'), findsOneWidget);

    await unmount(tester);
  });

  testWidgets('Attività lists the sede tickets and hides when there are none', (tester) async {
    await seedLocation(address: 'Via Roma 1', city: 'Milano');
    await seedTicket(locationId: 'loc-1', title: 'Sostituzione sifone bagno');

    await _pumpDetail(tester, db: db);

    expect(find.text('Sostituzione sifone bagno'), findsOneWidget);
    expect(find.textContaining('03/11/2026 · APERTO'), findsOneWidget);

    await unmount(tester);
  });

  testWidgets('hides Documenti & mappa, Sintesi and Attività when they have no data', (
    tester,
  ) async {
    await seedLocation(name: 'Sede senza indirizzo');

    await _pumpDetail(tester, db: db);

    expect(find.byType(GeoMapCard), findsNothing);
    expect(find.text('Documenti & mappa'), findsNothing);
    expect(find.text('Sintesi'), findsNothing);
    expect(find.text('Attività'), findsNothing);
    expect(find.text('Relazioni'), findsOneWidget); // the cliente row still exists

    await unmount(tester);
  });

  testWidgets('shows the unavailable state when the location is not synced locally', (
    tester,
  ) async {
    await _pumpDetail(tester, db: db, locationId: 'missing');

    expect(find.text('Sede non disponibile'), findsOneWidget);

    await unmount(tester);
  });

  // Same missing row, but on a device that has already synced: the sedi mirror arrived and simply
  // holds no such id, so promising a sync would never deliver it.
  testWidgets('a synced device reports the sede as not found, not as not downloaded', (
    tester,
  ) async {
    await db.setLastSync(DateTime.utc(2026, 10, 1));

    await _pumpDetail(tester, db: db, locationId: 'missing');

    expect(find.text('Sede non trovata'), findsOneWidget);
    expect(find.text('Sede non disponibile'), findsNothing);

    await unmount(tester);
  });

  testWidgets(
    'shows GeoMapCard, never a raw "Coordinate" row, when the location already has lat/lng',
    (tester) async {
      await seedLocation(address: 'Via Roma 1', city: 'Milano', latitude: 45.4642, longitude: 9.19);

      // Default 800px test surface: the embedded map's OSM attribution is a horizontal row that
      // overflows a 390px surface under the test font, and this test needs only the first section.
      await tester.pumpWidget(_buildDetail(db: db));
      // Bounded pumps, not pumpAndSettle: the cached lat/lng resolves with no real geocoding call,
      // so GeoMapCard mounts the real (offline, tile-less-in-tests) embedded map — its TileLayer's
      // network image requests never "settle" the way pumpAndSettle waits for.
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

      await _pumpDetail(tester, db: db);

      expect(find.byType(GeoMapCard), findsOneWidget);
      // The fake geocoder never resolves a point, so this exercises GeoMapCard's own fallback.
      expect(find.byType(AppMapCard), findsOneWidget);
      expect(find.text('Via Torino 5, Torino'), findsOneWidget);

      await unmount(tester);
    },
  );
}
