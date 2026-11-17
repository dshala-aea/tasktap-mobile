// test/golden/redesign/sede_detail_demo_test.dart
//
// Review artifact for the redesigned Sede detail. Seeds the local Drift mirror with the prototype's
// customer, sede, referente, contratto and tickets, then writes `build/redesign/sede_detail.png`.
// Nothing here compares images, so the test passes in CI.
//
// Run:
//   fvm flutter test test/golden/redesign/sede_detail_demo_test.dart

import 'dart:io';

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';
import 'package:tasktap_mobile/core/location/geocoding_service.dart';
import 'package:tasktap_mobile/data/entitlements/entitlement_providers.dart';
import 'package:tasktap_mobile/data/entitlements/entitlement_repository.dart';
import 'package:tasktap_mobile/data/local/app_database.dart' hide Entitlement;
import 'package:tasktap_mobile/data/sync/sync_service.dart'
    show appDatabaseProvider;
import 'package:tasktap_mobile/features/admin/locations/admin_location_detail_screen.dart';

import 'redesign_harness.dart';

/// flutter_map resolves its tile cache through `path_provider`, which has no platform
/// implementation in a widget test. Point it at a scratch directory instead of failing the capture.
class _FakePathProviderPlatform extends PathProviderPlatform
    with MockPlatformInterfaceMixin {
  _FakePathProviderPlatform(this._dir);

  final Directory _dir;

  @override
  Future<String?> getApplicationCachePath() async => _dir.path;

  @override
  Future<String?> getTemporaryPath() async => _dir.path;

  @override
  Future<String?> getApplicationSupportPath() async => _dir.path;

  @override
  Future<String?> getApplicationDocumentsPath() async => _dir.path;
}

/// No real Nominatim request: the seed carries lat/lng, and this keeps the fallback deterministic
/// if that ever changes.
class _NullGeocodingService extends GeocodingService {
  _NullGeocodingService() : super(dio: null);

  @override
  Future<GeocodedPoint?> geocode(String address) async => null;
}

Future<void> _seed(AppDatabase db) async {
  await db
      .into(db.customers)
      .insert(
        CustomersCompanion.insert(
          id: 'cust-rossi',
          tenantId: 'tenant-1',
          createdAt: DateTime.utc(2021, 4, 12),
          companyName: 'Rossi Srl',
        ),
      );

  await db
      .into(db.locations)
      .insert(
        LocationsCompanion.insert(
          id: 'loc-milano',
          tenantId: 'tenant-1',
          createdAt: DateTime.utc(2022, 1, 1),
          customerId: 'cust-rossi',
          name: 'Sede Milano',
          address: const Value('Via Roma 1'),
          city: const Value('Milano'),
          postalCode: const Value('20121'),
          phone: const Value('02 1234567'),
          notes: const Value('Citofono Rossi. Parcheggio nel cortile interno.'),
          latitude: const Value(45.4642),
          longitude: const Value(9.19),
        ),
      );

  await db
      .into(db.customerContacts)
      .insert(
        CustomerContactsCompanion.insert(
          id: 'contact-1',
          customerId: 'cust-rossi',
          name: 'Mario Bianchi',
          role: const Value('Responsabile impianti'),
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
          customerId: 'cust-rossi',
          locationId: const Value('loc-milano'),
          startDate: DateTime.utc(2026, 1, 1),
          endDate: Value(DateTime.utc(2026, 12, 31)),
          isActive: const Value(true),
        ),
      );

  await db
      .into(db.ticketStatuses)
      .insert(
        TicketStatusesCompanion.insert(
          id: const Value(1),
          tenantId: 'tenant-1',
          name: 'Aperto',
        ),
      );
  await db
      .into(db.ticketStatuses)
      .insert(
        TicketStatusesCompanion.insert(
          id: const Value(2),
          tenantId: 'tenant-1',
          name: 'Chiuso',
          isClosed: const Value(true),
        ),
      );

  Future<void> ticket(
    String id,
    String title,
    int statusId,
    DateTime createdAt,
  ) => db
      .into(db.tickets)
      .insert(
        TicketsCompanion.insert(
          id: id,
          tenantId: 'tenant-1',
          createdAt: createdAt,
          title: title,
          customerId: 'cust-rossi',
          locationId: 'loc-milano',
          statusId: statusId,
          typeId: 1,
        ),
      );

  await ticket(
    't1',
    'Perdita acqua sotto il lavello',
    1,
    DateTime.utc(2026, 11, 3),
  );
  await ticket(
    't2',
    'Sostituzione sifone bagno',
    2,
    DateTime.utc(2026, 10, 28),
  );
  await ticket('t3', 'Manutenzione caldaia', 2, DateTime.utc(2026, 10, 12));
}

void main() {
  late Directory tileCacheDir;

  setUpAll(loadRedesignFonts);

  setUp(() {
    tileCacheDir = Directory.systemTemp.createTempSync('sede_map_');
    PathProviderPlatform.instance = _FakePathProviderPlatform(tileCacheDir);
  });

  tearDown(() {
    if (tileCacheDir.existsSync()) tileCacheDir.deleteSync(recursive: true);
  });

  testWidgets('Sede detail — writes build/redesign/sede_detail.png', (
    tester,
  ) async {
    final db = AppDatabase(NativeDatabase.memory());
    await _seed(db);

    await captureRedesign(
      tester,
      'sede_detail',
      child: const AdminLocationDetailScreen(locationId: 'loc-milano'),
      overrides: [
        appDatabaseProvider.overrideWithValue(db),
        geocodingServiceProvider.overrideWithValue(_NullGeocodingService()),
        cachedEntitlementProvider.overrideWith(
          (ref) => Future.value(
            Entitlement(
              features: const {},
              capabilities: const {'clienti.location.write'},
              seatType: 'office',
              fetchedAt: DateTime.utc(2026, 9, 23),
            ),
          ),
        ),
      ],
    );

    await db.close();
  });
}
