// test/golden/redesign/contratto_detail_demo_test.dart
//
// Review artifact for the redesigned Contratto detail: the prototype's Full service contract,
// rendered from the local mirror at 390×844 and written to `build/redesign/contratto_detail.png`.
// Nothing here compares images, so the test passes in CI.
//
// Run:
//   fvm flutter test test/golden/redesign/contratto_detail_demo_test.dart

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tasktap_mobile/core/time/business_time.dart';
import 'package:tasktap_mobile/core/time/business_time_providers.dart';
import 'package:tasktap_mobile/data/entitlements/entitlement_providers.dart';
import 'package:tasktap_mobile/data/entitlements/entitlement_repository.dart';
import 'package:tasktap_mobile/data/local/app_database.dart' hide Entitlement;
import 'package:tasktap_mobile/data/sync/sync_service.dart'
    show appDatabaseProvider;
import 'package:tasktap_mobile/features/admin/contracts/admin_contract_detail_screen.dart';

import 'redesign_harness.dart';

/// Wednesday 4 November 2026, 12:00 Rome — the prototype board's "today".
final _now = DateTime.utc(2026, 11, 4, 11);

const _contract = <String, dynamic>{
  'id': 'contract-full-service',
  'name': 'Full service',
  'numero': 'CTR-2026-014',
  'codice': 'FS-014',
  'tipo': 'Manutenzione',
  'externalId': 'EXT-014',
  'description':
      'Manutenzione programmata della caldaia e dell\'impianto idraulico.',
  'condizioni': 'Pagamento a 30 giorni',
  'notes': 'Accesso dal cortile interno.',
  'customerId': 'cust-rossi',
  'locationId': 'loc-milano',
  'startDate': '2026-01-01T00:00:00Z',
  'endDate': '2026-12-31T00:00:00Z',
  'autoRenewal': true,
  'scadenzaGiorni': 30,
  'frequencyValue': 1,
  'frequencyUnit': 'Months',
  'price': 4800,
  'isActive': true,
};

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
        ),
      );

  Future<void> status(int id, String name) => db
      .into(db.ticketStatuses)
      .insert(
        TicketStatusesCompanion.insert(
          id: Value(id),
          tenantId: 'tenant-1',
          name: name,
        ),
      );
  await status(1, 'In corso');
  await status(2, 'Aperto');
  await status(3, 'Chiuso');

  Future<void> ticket({
    required String id,
    required String title,
    required DateTime createdAt,
    required int statusId,
  }) => db
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
          contractId: const Value('contract-full-service'),
        ),
      );
  await ticket(
    id: 'ticket-1',
    title: 'Manutenzione caldaia',
    createdAt: DateTime.utc(2026, 10, 3),
    statusId: 3,
  );
  await ticket(
    id: 'ticket-2',
    title: 'Perdita acqua sotto il lavello',
    createdAt: DateTime.utc(2026, 9, 18),
    statusId: 3,
  );
  await ticket(
    id: 'ticket-3',
    title: 'Sostituzione filtro',
    createdAt: DateTime.utc(2026, 8, 7),
    statusId: 3,
  );

  Future<void> schedule(String id, String ticketId, DateTime date) => db
      .into(db.schedules)
      .insert(
        SchedulesCompanion.insert(
          id: id,
          tenantId: 'tenant-1',
          createdAt: DateTime.utc(2026, 1, 1),
          activityDate: date,
          timeStartMinutes: 540,
          timeEndMinutes: 600,
          userId: 'u-daniel',
          statusId: 1,
          locationId: 'loc-milano',
          title: 'Manutenzione programmata',
          description: '',
          ticketId: Value(ticketId),
        ),
      );
  await schedule('sched-1', 'ticket-1', DateTime.utc(2026, 10, 3));
  await schedule('sched-2', 'ticket-2', DateTime.utc(2026, 9, 18));
}

List<Override> _overrides(AppDatabase db) => [
  appDatabaseProvider.overrideWithValue(db),
  businessTimeProvider.overrideWithValue(
    BusinessTime('Europe/Rome', clock: () => _now),
  ),
  cachedEntitlementProvider.overrideWith(
    (ref) => Future.value(
      Entitlement(
        features: const {},
        capabilities: const {
          'contratti.contract.write',
          'pianificazione.schedule.write',
        },
        seatType: 'office',
        fetchedAt: DateTime.utc(2026, 1, 1),
      ),
    ),
  ),
];

void main() {
  setUpAll(() async {
    ensureTimeZonesInitialized();
    await loadRedesignFonts();
  });

  testWidgets('Contratto detail — writes build/redesign/contratto_detail.png', (
    tester,
  ) async {
    final db = AppDatabase(NativeDatabase.memory());
    await _seed(db);

    await captureRedesign(
      tester,
      'contratto_detail',
      child: const AdminContractDetailScreen(contract: _contract),
      overrides: _overrides(db),
    );

    await db.close();
  });

  testWidgets(
    'Contratto detail, full page — writes build/redesign/contratto_detail_full.png',
    (tester) async {
      final db = AppDatabase(NativeDatabase.memory());
      await _seed(db);

      // The 844px review frame stops at the top of Attività; this taller capture exists so the
      // whole section stack can be compared with the prototype.
      await captureRedesign(
        tester,
        'contratto_detail_full',
        size: const Size(390, 1200),
        child: const AdminContractDetailScreen(contract: _contract),
        overrides: _overrides(db),
      );

      await db.close();
    },
  );
}
