// test/golden/redesign/cantiere_detail_demo_test.dart
//
// Proof that the redesign capture harness works, not a redesign of this screen: the wave-1
// Cantiere detail (`lib/features/cantiere/cantiere_detail_screen.dart`) is rendered with a
// realistic local fixture and written to `build/redesign/cantiere_detail.png`.
//
// Run:
//   fvm flutter test test/golden/redesign/cantiere_detail_demo_test.dart
//
// The PNG is a review artifact only — nothing here compares images, so the test passes in CI.

import 'package:dio/dio.dart';
import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tasktap_mobile/core/location/geocoding_service.dart';
import 'package:tasktap_mobile/data/entitlements/entitlement_providers.dart';
import 'package:tasktap_mobile/data/entitlements/entitlement_repository.dart';
import 'package:tasktap_mobile/data/local/app_database.dart' hide Entitlement;
import 'package:tasktap_mobile/data/sync/connectivity_provider.dart';
import 'package:tasktap_mobile/data/sync/sync_service.dart'
    show appDatabaseProvider;
import 'package:tasktap_mobile/data/timbratura/cantiere_worklog_api_client.dart';
import 'package:tasktap_mobile/features/cantiere/cantiere_detail_screen.dart';
import 'package:tasktap_mobile/features/ticket/ticket_providers.dart'
    show commessaByIdProvider;
import 'package:tasktap_mobile/presentation/providers/auth_providers.dart'
    show internalUserIdProvider;

import 'redesign_harness.dart';

/// No real Nominatim request: the wave-1 screen draws the map art itself, but the geocoded-location
/// provider must still be deterministic if a future revision reads it.
class _NullGeocodingService extends GeocodingService {
  _NullGeocodingService() : super(dio: null);

  @override
  Future<GeocodedPoint?> geocode(String address) async => null;
}

/// The crew is a live endpoint; answer it from the fixture instead of a real HTTP call.
class _CrewApiClient extends CantiereWorklogApiClient {
  _CrewApiClient() : super(Dio());

  @override
  Future<List<CantiereWorkLogDto>> getActive() async => const [];

  @override
  Future<List<CantiereCrewAssignmentDto>> getAssegnazioni(
    String cantiereId,
  ) async => const [
    CantiereCrewAssignmentDto(id: 'a1', userId: 'u1', isLead: true),
    CantiereCrewAssignmentDto(id: 'a2', userId: 'u2', isLead: false),
    CantiereCrewAssignmentDto(id: 'a3', userId: 'u3', isLead: false),
  ];
}

Future<void> _seedCantiere(AppDatabase db) async {
  // Two hours and a bit on site, so the live hero matches the prototype's 02:14 state.
  final ingress = DateTime.now().subtract(
    const Duration(hours: 2, minutes: 14),
  );

  await db
      .into(db.customers)
      .insert(
        CustomersCompanion.insert(
          id: 'cust-1',
          tenantId: 'tenant-1',
          createdAt: DateTime.utc(2026, 1, 1),
          companyName: 'Rossi Srl',
        ),
      );

  await db
      .into(db.cantieri)
      .insert(
        CantieriCompanion.insert(
          id: 'c1',
          tenantId: 'tenant-1',
          createdAt: DateTime.utc(2026, 1, 1),
          name: 'Ristrutturazione Via Roma',
          address: const Value('Via Roma 1'),
          city: const Value('Milano'),
          postalCode: const Value('20121'),
          customerId: const Value('cust-1'),
          commessaId: const Value('com-1'),
          startDate: Value(DateTime.utc(2026, 11, 1)),
          endDate: Value(DateTime.utc(2026, 12, 15)),
          notes: const Value('Accesso dal cortile interno.'),
        ),
      );

  await db
      .into(db.ticketStatuses)
      .insert(
        TicketStatusesCompanion.insert(
          id: const Value(1),
          tenantId: 'tenant-1',
          name: 'In corso',
          isInProgress: const Value(true),
        ),
      );
  await db
      .into(db.ticketStatuses)
      .insert(
        TicketStatusesCompanion.insert(
          id: const Value(2),
          tenantId: 'tenant-1',
          name: 'Aperto',
        ),
      );

  await db
      .into(db.tickets)
      .insert(
        TicketsCompanion.insert(
          id: 't1',
          tenantId: 'tenant-1',
          createdAt: DateTime.utc(2026, 11, 1),
          title: 'Perdita acqua sotto il lavello',
          customerId: 'cust-1',
          locationId: 'loc-1',
          statusId: 1,
          typeId: 1,
          cantiereId: const Value('c1'),
        ),
      );
  await db
      .into(db.tickets)
      .insert(
        TicketsCompanion.insert(
          id: 't2',
          tenantId: 'tenant-1',
          createdAt: DateTime.utc(2026, 11, 2),
          title: 'Sostituzione sifone bagno',
          customerId: 'cust-1',
          locationId: 'loc-1',
          statusId: 2,
          typeId: 1,
          cantiereId: const Value('c1'),
        ),
      );

  await db
      .into(db.colleagues)
      .insert(
        ColleaguesCompanion.insert(id: 'u1', displayName: 'Daniel Shala'),
      );
  await db
      .into(db.colleagues)
      .insert(ColleaguesCompanion.insert(id: 'u2', displayName: 'Marco Rossi'));
  await db
      .into(db.colleagues)
      .insert(
        ColleaguesCompanion.insert(id: 'u3', displayName: 'Luca Bianchi'),
      );

  await db
      .into(db.cantierePunches)
      .insert(
        CantierePunchesCompanion.insert(
          id: 'p1',
          eventTime: ingress,
          eventType: 'ingresso',
          cantiereId: const Value('c1'),
          customerId: const Value('cust-1'),
          isPendingSync: const Value(false),
        ),
      );

  await db
      .into(db.cantiereWorkLogs)
      .insert(
        CantiereWorkLogsCompanion.insert(
          id: 'w1',
          cantiereId: 'c1',
          userId: 'u1',
          workDate: DateTime.utc(2026, 11, 3),
          startSeconds: 8 * 3600,
          endSeconds: const Value(12 * 3600 + 30 * 60),
          approvalStatus: const Value(2),
          createdAt: DateTime.utc(2026, 11, 3, 6),
        ),
      );
}

void main() {
  setUpAll(loadRedesignFonts);

  testWidgets('Cantiere detail — writes build/redesign/cantiere_detail.png', (
    tester,
  ) async {
    final db = AppDatabase(NativeDatabase.memory());
    await _seedCantiere(db);

    await captureRedesign(
      tester,
      'cantiere_detail',
      child: const CantiereDetailScreen(cantiereId: 'c1'),
      overrides: [
        appDatabaseProvider.overrideWithValue(db),
        geocodingServiceProvider.overrideWithValue(_NullGeocodingService()),
        cantiereWorklogApiClientProvider.overrideWithValue(_CrewApiClient()),
        isOnlineProvider.overrideWithValue(true),
        internalUserIdProvider.overrideWith((ref) async => 'u1'),
        cachedEntitlementProvider.overrideWith(
          (ref) => Future.value(
            Entitlement(
              features: const {},
              capabilities: const {'cantieri.cantiere.write'},
              seatType: 'office',
              fetchedAt: DateTime.utc(2026, 1, 1),
            ),
          ),
        ),
        // The dossier cell is answered directly rather than through the admin API's live lookup.
        commessaByIdProvider.overrideWith(
          (ref, id) async => <String, dynamic>{
            'id': id,
            'codice': 'CM-2026-018',
          },
        ),
      ],
    );

    await db.close();
  });
}
