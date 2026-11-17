// test/golden/redesign/report_detail_demo_test.dart
//
// Review artifact for the redesigned Report admin detail. Writes
// `build/redesign/report_detail.png`; nothing here compares images.

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:tasktap_mobile/data/local/app_database.dart';
import 'package:tasktap_mobile/data/sync/connectivity_provider.dart';
import 'package:tasktap_mobile/data/sync/sync_service.dart' show appDatabaseProvider;
import 'package:tasktap_mobile/features/admin/reports/admin_report_detail_screen.dart';

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
      .into(db.locations)
      .insert(
        LocationsCompanion.insert(
          id: 'loc-1',
          tenantId: 'tenant-1',
          createdAt: DateTime.utc(2026, 1, 1),
          customerId: 'cust-1',
          name: 'Sede Milano',
          address: const Value('Via Roma 1'),
          city: const Value('Milano'),
        ),
      );
  await db
      .into(db.reportAllegati)
      .insert(
        ReportAllegatiCompanion.insert(
          id: 'photo-1',
          tenantId: 'tenant-1',
          createdAt: DateTime.utc(2026, 11, 3, 9),
          fileName: 'foto_lavello.jpg',
          contentType: 'image/jpeg',
          sizeBytes: 2048,
          storagePath: '',
          url: '/api/reports/r1/attachments/photo-1/content',
          entityType: 1,
          entityId: 'r1',
          uploadedByUserId: 'u-1',
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
        ),
      );
}

void main() {
  setUpAll(() async {
    await loadRedesignFonts();
    await initializeDateFormatting('it');
  });

  testWidgets('Report admin detail — writes build/redesign/report_detail.png', (tester) async {
    final db = AppDatabase(NativeDatabase.memory());
    await _seed(db);

    await captureRedesign(
      tester,
      'report_detail',
      child: const AdminReportDetailScreen(
        report: {
          'id': 'r1',
          'title': 'Rapportino 2026-0412',
          'numero': '2026-0412',
          'stato': 'Inviato',
          'customerId': 'cust-1',
          'locationId': 'loc-1',
          'ticketId': 't1',
          'createdAt': '2026-11-03T08:00:00Z',
          'startedAt': '2026-11-03T08:00:00Z',
          'endedAt': '2026-11-04T14:00:00Z',
          'inviatoAt': '2026-11-04T15:00:00Z',
          'customerSignatureAllegatoId': 'a1',
          'technicianSignatureAllegatoId': 'a2',
          'technicianNotes': 'Accesso dal cortile interno.',
        },
      ),
      overrides: [
        appDatabaseProvider.overrideWithValue(db),
        isOnlineProvider.overrideWithValue(false),
      ],
    );

    await db.close();
  });
}
