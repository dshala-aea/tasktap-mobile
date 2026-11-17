// test/golden/redesign/cantieri_list_demo_test.dart
//
// Review artifact for the wave-1 Cantieri list redesign. Renders the technician list with a
// realistic local fixture and writes `build/redesign/cantieri_list.png`; nothing here compares
// images, so the test passes in CI.
//
// Run:
//   fvm flutter test test/golden/redesign/cantieri_list_demo_test.dart

import 'package:dio/dio.dart';
import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tasktap_mobile/core/time/business_time.dart';
import 'package:tasktap_mobile/data/local/app_database.dart';
import 'package:tasktap_mobile/data/sync/connectivity_provider.dart';
import 'package:tasktap_mobile/data/sync/sync_service.dart'
    show appDatabaseProvider;
import 'package:tasktap_mobile/data/timbratura/cantiere_worklog_api_client.dart';
import 'package:tasktap_mobile/features/cantiere/cantieri_list_screen.dart';

import 'redesign_harness.dart';

/// No real `/api/cantiereworklog` request from the active-session fallback.
class _EmptyWorklogApiClient extends CantiereWorklogApiClient {
  _EmptyWorklogApiClient() : super(Dio());

  @override
  Future<List<CantiereWorkLogDto>> getActive() async => const [];
}

Future<void> _seed(AppDatabase db) async {
  final bt = BusinessTime.fallback();
  final today = bt.utcRangeForBusinessDate(bt.businessToday()).$1;

  Future<void> customer(String id, String name) => db
      .into(db.customers)
      .insert(
        CustomersCompanion.insert(
          id: id,
          tenantId: 'tenant-1',
          createdAt: DateTime.utc(2026, 1, 1),
          companyName: name,
        ),
      );

  await customer('cust-rossi', 'Rossi Srl');
  await customer('cust-bianchi', 'Bianchi Srl');
  await customer('cust-verdi', 'Verdi Spa');
  await customer('cust-gialli', 'Gialli Srl');
  await customer('cust-neri', 'Neri Srl');

  Future<void> cantiere({
    required String id,
    required String name,
    required String customerId,
    required String city,
    int status = 0,
    DateTime? startDate,
    DateTime? endDate,
  }) => db
      .into(db.cantieri)
      .insert(
        CantieriCompanion.insert(
          id: id,
          tenantId: 'tenant-1',
          createdAt: DateTime.utc(2026, 1, 1),
          name: name,
          city: Value(city),
          customerId: Value(customerId),
          status: Value(status),
          startDate: Value(startDate),
          endDate: Value(endDate),
        ),
      );

  await cantiere(
    id: 'c1',
    name: 'Ristrutturazione Via Roma',
    customerId: 'cust-rossi',
    city: 'Milano',
    startDate: today.subtract(const Duration(days: 5)),
    endDate: today.add(const Duration(days: 20)),
  );
  await cantiere(
    id: 'c2',
    name: 'Manutenzione caldaie',
    customerId: 'cust-bianchi',
    city: 'Milano',
    startDate: today.subtract(const Duration(days: 2)),
  );
  await cantiere(
    id: 'c3',
    name: 'Cantiere Nord',
    customerId: 'cust-verdi',
    city: 'Sesto',
    startDate: today.subtract(const Duration(days: 10)),
  );
  await cantiere(
    id: 'c4',
    name: 'Pulizia impianti',
    customerId: 'cust-gialli',
    city: 'Monza',
    startDate: today.subtract(const Duration(days: 30)),
  );
  await cantiere(
    id: 'c5',
    name: 'Sostituzione infissi',
    customerId: 'cust-neri',
    city: 'Milano',
    startDate: today.add(const Duration(days: 10)),
  );

  Future<void> crew(String cantiereId, int count) async {
    for (var i = 0; i < count; i++) {
      await db
          .into(db.cantiereCrewAssignments)
          .insert(
            CantiereCrewAssignmentsCompanion.insert(
              id: '$cantiereId-a$i',
              cantiereId: cantiereId,
              userId: 'u$i',
            ),
          );
    }
  }

  await crew('c1', 3);
  await crew('c2', 2);
  await crew('c3', 4);
  await crew('c4', 2);

  Future<void> closedInterval(
    String cantiereId,
    int hour,
    int minutes,
    int durationHours,
    int durationMinutes,
  ) async {
    final start = today.add(Duration(hours: hour, minutes: minutes));
    final end = start.add(
      Duration(hours: durationHours, minutes: durationMinutes),
    );
    await db
        .into(db.cantierePunches)
        .insert(
          CantierePunchesCompanion.insert(
            id: '$cantiereId-in',
            eventTime: start,
            eventType: 'ingresso',
            cantiereId: Value(cantiereId),
          ),
        );
    await db
        .into(db.cantierePunches)
        .insert(
          CantierePunchesCompanion.insert(
            id: '$cantiereId-out',
            eventTime: end,
            eventType: 'uscita',
          ),
        );
  }

  await closedInterval('c1', 8, 30, 2, 30);
  await closedInterval('c2', 12, 0, 2, 0);

  await db.setLastSync(DateTime.now());
}

void main() {
  setUpAll(loadRedesignFonts);

  testWidgets('Cantieri list — writes build/redesign/cantieri_list.png', (
    tester,
  ) async {
    final db = AppDatabase(NativeDatabase.memory());
    await _seed(db);

    await captureRedesign(
      tester,
      'cantieri_list',
      child: const CantieriListScreen(),
      overrides: [
        appDatabaseProvider.overrideWithValue(db),
        cantiereWorklogApiClientProvider.overrideWithValue(
          _EmptyWorklogApiClient(),
        ),
        isOnlineProvider.overrideWithValue(true),
      ],
    );

    await db.close();
  });
}
