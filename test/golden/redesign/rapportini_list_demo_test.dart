// test/golden/redesign/rapportini_list_demo_test.dart
//
// Review artifact for the Rapportini list: the real screen rendered with a Drift fixture shaped
// like the prototype's `rapportini` entry. Writes `build/redesign/rapportini_list.png`; nothing
// here compares images, so the test passes in CI.
//
// Run:
//   fvm flutter test test/golden/redesign/rapportini_list_demo_test.dart

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';

import 'package:tasktap_mobile/data/local/app_database.dart';
import 'package:tasktap_mobile/data/sync/connectivity_provider.dart'
    show ConnectivityNotifier, connectivityProvider;
import 'package:tasktap_mobile/data/sync/pending_sync_count_provider.dart';
import 'package:tasktap_mobile/data/sync/sync_service.dart'
    show appDatabaseProvider, lastSyncProvider;
import 'package:tasktap_mobile/features/rapportino/rapportini_list_screen.dart';

import 'redesign_harness.dart';

class _FakeConnectivity extends ConnectivityNotifier {
  @override
  Future<bool> build() async => true;
}

void main() {
  setUpAll(() async {
    driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
    await initializeDateFormatting('it', null);
    await loadRedesignFonts();
  });

  testWidgets('rapportini list with the prototype fixture', (tester) async {
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    await db.setLastSync(DateTime.utc(2026, 11, 12));

    await _seedCustomer(db, id: 'cus-rossi', name: 'Rossi Srl');
    await _seedCustomer(db, id: 'cus-bianchi', name: 'Bianchi Srl');
    await _seedCustomer(db, id: 'cus-verdi', name: 'Verdi Spa');
    await _seedLocation(
      db,
      id: 'loc-rossi',
      customerId: 'cus-rossi',
      name: 'Milano',
    );
    await _seedLocation(
      db,
      id: 'loc-bianchi',
      customerId: 'cus-bianchi',
      name: 'Sesto',
    );
    await _seedLocation(
      db,
      id: 'loc-verdi',
      customerId: 'cus-verdi',
      name: 'Monza',
    );

    final today = DateTime.now().toUtc();

    await _seedDraft(
      db,
      id: 'r-412',
      title: 'Rapportino 2026-0412',
      customerId: 'cus-rossi',
      locationId: 'loc-rossi',
      technicianSignatureId: 'tech-sig-412',
      customerSignatureId: 'cust-sig-412',
      createdAt: today,
      updatedAt: today,
    );
    await _seedHours(db, reportId: 'r-412', hours: 4.5);

    await _seedDraft(
      db,
      id: 'r-411',
      title: 'Rapportino 2026-0411',
      customerId: 'cus-bianchi',
      locationId: 'loc-bianchi',
      technicianSignatureId: 'tech-sig-411',
      createdAt: today,
      updatedAt: today,
    );
    await _seedHours(db, reportId: 'r-411', hours: 2);

    await _seedDraft(
      db,
      id: 'r-409',
      title: 'Rapportino 2026-0409',
      customerId: 'cus-verdi',
      locationId: 'loc-verdi',
      stato: 'Inviato',
      submissionState: 'submitted',
      isLocalOnly: false,
      technicianSignatureId: 'tech-sig-409',
      customerSignatureId: 'cust-sig-409',
      createdAt: DateTime.utc(2026, 11, 12, 9),
      updatedAt: DateTime.utc(2026, 11, 12, 9),
    );
    await _seedHours(db, reportId: 'r-409', hours: 6);

    await captureRedesign(
      tester,
      'rapportini_list',
      child: const RapportiniListScreen(),
      overrides: [
        appDatabaseProvider.overrideWithValue(db),
        connectivityProvider.overrideWith(() => _FakeConnectivity()),
        pendingSyncCountProvider.overrideWith(
          (ref) => Stream.value((pending: 0, failed: 0)),
        ),
        lastSyncProvider.overrideWith(
          (ref) => Stream.value(DateTime.utc(2026, 11, 12)),
        ),
      ],
    );
  });
}

Future<void> _seedCustomer(
  AppDatabase db, {
  required String id,
  required String name,
}) async {
  await db
      .into(db.customers)
      .insert(
        CustomersCompanion.insert(
          id: id,
          tenantId: 'tenant-1',
          createdAt: DateTime.utc(2026, 1, 1),
          companyName: name,
        ),
      );
}

Future<void> _seedLocation(
  AppDatabase db, {
  required String id,
  required String customerId,
  required String name,
}) async {
  await db
      .into(db.locations)
      .insert(
        LocationsCompanion.insert(
          id: id,
          tenantId: 'tenant-1',
          createdAt: DateTime.utc(2026, 1, 1),
          customerId: customerId,
          name: name,
        ),
      );
}

Future<void> _seedDraft(
  AppDatabase db, {
  required String id,
  required String title,
  required String customerId,
  required String locationId,
  String stato = 'Bozza',
  String submissionState = 'draft',
  bool isLocalOnly = true,
  String? technicianSignatureId,
  String? customerSignatureId,
  DateTime? createdAt,
  DateTime? updatedAt,
}) async {
  await db
      .into(db.draftReports)
      .insert(
        DraftReportsCompanion.insert(
          id: id,
          tenantId: 'tenant-1',
          createdAt: createdAt ?? DateTime.utc(2026, 11, 12),
          updatedAt: Value(updatedAt),
          title: title,
          insertedUserId: 'user-1',
          customerId: Value(customerId),
          locationId: locationId,
          isLocalOnly: Value(isLocalOnly),
          stato: Value(stato),
          submissionState: Value(submissionState),
          technicianSignatureAllegatoId: Value(technicianSignatureId),
          customerSignatureAllegatoId: Value(customerSignatureId),
        ),
      );
}

Future<void> _seedHours(
  AppDatabase db, {
  required String reportId,
  required double hours,
}) async {
  await db
      .into(db.reportStaffTable)
      .insert(
        ReportStaffTableCompanion.insert(
          id: 'staff-$reportId',
          tenantId: 'tenant-1',
          createdAt: DateTime.utc(2026, 11, 12),
          reportId: reportId,
          userId: 'user-1',
          hoursWorked: Value(hours),
        ),
      );
}
