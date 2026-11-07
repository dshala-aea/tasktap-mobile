// test/golden/redesign/commessa_detail_demo_test.dart
//
// Review artifact for the wave-1 Commessa detail redesign: renders the screen with a realistic
// local fixture and writes `build/redesign/commessa_detail.png`.
//
// Run:
//   fvm flutter test test/golden/redesign/commessa_detail_demo_test.dart
//
// The PNG is a review artifact only — nothing here compares images, so the test passes in CI.

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tasktap_mobile/data/local/app_database.dart';
import 'package:tasktap_mobile/data/sync/connectivity_provider.dart';
import 'package:tasktap_mobile/data/sync/sync_service.dart'
    show appDatabaseProvider;
import 'package:tasktap_mobile/features/admin/commesse/admin_commessa_detail_screen.dart';
import 'package:tasktap_mobile/features/ticket/ticket_providers.dart'
    show commessaByIdProvider;

import 'redesign_harness.dart';

Future<void> _seed(AppDatabase db) async {
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
          createdAt: DateTime.utc(2026, 11, 1),
          name: 'Ristrutturazione Via Roma',
          city: const Value('Milano'),
          customerId: const Value('cust-1'),
          commessaId: const Value('comm-1'),
        ),
      );
  await db
      .into(db.cantieri)
      .insert(
        CantieriCompanion.insert(
          id: 'c2',
          tenantId: 'tenant-1',
          createdAt: DateTime.utc(2026, 11, 2),
          name: 'Manutenzione uffici',
          city: const Value('Torino'),
          customerId: const Value('cust-1'),
          commessaId: const Value('comm-1'),
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
          name: 'In corso',
          isInProgress: const Value(true),
        ),
      );
  await db
      .into(db.ticketStatuses)
      .insert(
        TicketStatusesCompanion.insert(
          id: const Value(3),
          tenantId: 'tenant-1',
          name: 'Completato',
          isClosed: const Value(true),
        ),
      );

  Future<void> ticket(String id, String numero, String title, int statusId) {
    return db
        .into(db.tickets)
        .insert(
          TicketsCompanion.insert(
            id: id,
            tenantId: 'tenant-1',
            createdAt: DateTime.utc(2026, 11, 1),
            title: title,
            numero: Value(numero),
            customerId: 'cust-1',
            locationId: 'loc-1',
            statusId: statusId,
            typeId: 1,
            commessaId: const Value('comm-1'),
          ),
        );
  }

  await ticket('t1', 'TKT-0142', 'Perdita acqua sotto il lavello', 1);
  await ticket('t2', 'TKT-0148', 'Sostituzione sifone bagno', 2);
  await ticket('t3', 'TKT-0151', 'Riparazione rubinetto cucina', 3);
}

void main() {
  setUpAll(loadRedesignFonts);

  testWidgets('Commessa detail — writes build/redesign/commessa_detail.png', (
    tester,
  ) async {
    final db = AppDatabase(NativeDatabase.memory());
    await _seed(db);

    await captureRedesign(
      tester,
      'commessa_detail',
      child: const AdminCommessaDetailScreen(commessaId: 'comm-1'),
      overrides: [
        appDatabaseProvider.overrideWithValue(db),
        isOnlineProvider.overrideWithValue(true),
        commessaByIdProvider.overrideWith(
          (ref, id) async => <String, dynamic>{
            'id': id,
            'codice': 'CM-2026-018',
            'descrizione': 'Ristrutturazione impianto idraulico',
            'stato': 'Aperta',
            'customerId': 'cust-1',
            'dataApertura': '2026-11-01T00:00:00Z',
            'dataChiusura': '2026-12-15T00:00:00Z',
            'importo': 48000.0,
            'note': 'Accesso dal cortile interno. Coordinate con il custode.',
          },
        ),
      ],
    );

    await db.close();
  });
}
