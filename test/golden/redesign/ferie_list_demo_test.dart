// test/golden/redesign/ferie_list_demo_test.dart
//
// Review artifact for the redesigned Ferie e permessi list. Seeds the local absence-request
// mirror with the prototype's groups (pending, approved) and a colleague for the person line,
// then writes `build/redesign/ferie_list.png`; nothing here compares images, so the test passes
// in CI.
//
// Run:
//   fvm flutter test test/golden/redesign/ferie_list_demo_test.dart

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:tasktap_mobile/data/entitlements/entitlement_service.dart'
    show internalUserIdPrefsKey;
import 'package:tasktap_mobile/data/local/app_database.dart';
import 'package:tasktap_mobile/data/sync/connectivity_provider.dart';
import 'package:tasktap_mobile/data/sync/sync_service.dart'
    show appDatabaseProvider;
import 'package:tasktap_mobile/features/ferie/ferie_permessi_list_screen.dart';

import 'redesign_harness.dart';

class _FakeConnectivity extends ConnectivityNotifier {
  @override
  Future<bool> build() async => false;
}

Future<void> _seed(AppDatabase db) async {
  await db
      .into(db.colleagues)
      .insert(
        ColleaguesCompanion.insert(id: 'user-1', displayName: 'Daniel Shala'),
      );

  Future<void> request({
    required String id,
    required int type,
    required String startDate,
    required String endDate,
    required int status,
    String? startTime,
    String? endTime,
    required DateTime createdAt,
  }) => db
      .into(db.absenceRequests)
      .insert(
        AbsenceRequestsCompanion.insert(
          id: id,
          requestedByUserId: 'user-1',
          createdByUserId: 'user-1',
          type: type,
          startDate: startDate,
          endDate: endDate,
          startTime: Value(startTime),
          endTime: Value(endTime),
          status: status,
          createdAt: createdAt,
        ),
      );

  await request(
    id: 'ar-1',
    type: 0,
    startDate: '2026-11-18',
    endDate: '2026-11-22',
    status: 0,
    createdAt: DateTime.utc(2026, 11, 5, 8),
  );
  await request(
    id: 'ar-2',
    type: 1,
    startDate: '2026-11-12',
    endDate: '2026-11-12',
    startTime: '09:00:00',
    endTime: '11:00:00',
    status: 0,
    createdAt: DateTime.utc(2026, 11, 4, 8),
  );
  await request(
    id: 'ar-3',
    type: 0,
    startDate: '2026-12-02',
    endDate: '2026-12-06',
    status: 1,
    createdAt: DateTime.utc(2026, 11, 1, 8),
  );

  await db.setLastSync(DateTime.utc(2026, 11, 5));
}

void main() {
  setUpAll(() async {
    await initializeDateFormatting('it', null);
    await loadRedesignFonts();
  });

  setUp(() {
    SharedPreferences.setMockInitialValues({internalUserIdPrefsKey: 'user-1'});
  });

  testWidgets('Ferie e permessi list — writes build/redesign/ferie_list.png', (
    tester,
  ) async {
    final db = AppDatabase(NativeDatabase.memory());
    await _seed(db);

    await captureRedesign(
      tester,
      'ferie_list',
      child: const FeriePermessiListScreen(),
      overrides: [
        appDatabaseProvider.overrideWithValue(db),
        connectivityProvider.overrideWith(_FakeConnectivity.new),
      ],
    );

    await db.close();
  });
}
