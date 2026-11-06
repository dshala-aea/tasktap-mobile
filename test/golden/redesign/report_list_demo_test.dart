// test/golden/redesign/report_list_demo_test.dart
//
// Review artifact for the redesigned Report admin list. Seeds the local mirror with the
// prototype's rows and writes `build/redesign/report_list.png`. Nothing here compares images.

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:tasktap_mobile/data/local/app_database.dart';
import 'package:tasktap_mobile/data/sync/connectivity_provider.dart';
import 'package:tasktap_mobile/data/sync/sync_service.dart' show appDatabaseProvider;
import 'package:tasktap_mobile/features/admin/reports/admin_report_list_screen.dart';

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
      .into(db.customers)
      .insert(
        CustomersCompanion.insert(
          id: 'cust-2',
          tenantId: 'tenant-1',
          createdAt: DateTime.utc(2026, 1, 1),
          companyName: 'Bianchi Srl',
        ),
      );
  await db
      .into(db.customers)
      .insert(
        CustomersCompanion.insert(
          id: 'cust-3',
          tenantId: 'tenant-1',
          createdAt: DateTime.utc(2026, 1, 1),
          companyName: 'Verdi Spa',
        ),
      );

  Future<void> add({
    required String id,
    required String numero,
    required String stato,
    required String customerId,
    required DateTime startedAt,
    required DateTime endedAt,
    DateTime? inviatoAt,
    DateTime? controllatoAt,
  }) => db
      .into(db.draftReports)
      .insert(
        DraftReportsCompanion.insert(
          id: id,
          tenantId: 'tenant-1',
          createdAt: startedAt,
          title: 'Rapportino $numero',
          numero: Value(numero),
          insertedUserId: 'user-1',
          locationId: 'loc-1',
          customerId: Value(customerId),
          stato: Value(stato),
          startedAt: Value(startedAt),
          endedAt: Value(endedAt),
          inviatoAt: Value(inviatoAt),
          controllatoAt: Value(controllatoAt),
        ),
      );

  await add(
    id: 'r1',
    numero: '2026-0412',
    stato: 'Inviato',
    customerId: 'cust-1',
    startedAt: DateTime.utc(2026, 11, 3, 8),
    endedAt: DateTime.utc(2026, 11, 4, 14),
    inviatoAt: DateTime.utc(2026, 11, 4, 15),
  );
  await add(
    id: 'r2',
    numero: '2026-0411',
    stato: 'Inviato',
    customerId: 'cust-2',
    startedAt: DateTime.utc(2026, 11, 3, 8),
    endedAt: DateTime.utc(2026, 11, 4, 2),
    inviatoAt: DateTime.utc(2026, 11, 4, 3),
  );
  await add(
    id: 'r3',
    numero: '2026-0409',
    stato: 'Controllato',
    customerId: 'cust-3',
    startedAt: DateTime.utc(2026, 10, 20, 8),
    endedAt: DateTime.utc(2026, 10, 21, 6),
    inviatoAt: DateTime.utc(2026, 10, 21, 9),
    controllatoAt: DateTime.utc(2026, 10, 22, 10),
  );
}

void main() {
  setUpAll(() async {
    await loadRedesignFonts();
    await initializeDateFormatting('it');
  });

  testWidgets('Report admin list — writes build/redesign/report_list.png', (tester) async {
    final db = AppDatabase(NativeDatabase.memory());
    await _seed(db);
    await db.setLastSync(DateTime.utc(2026, 11, 5));

    await captureRedesign(
      tester,
      'report_list',
      child: const AdminReportListScreen(),
      overrides: [
        appDatabaseProvider.overrideWithValue(db),
        isOnlineProvider.overrideWithValue(false),
      ],
    );

    await db.close();
  });
}
