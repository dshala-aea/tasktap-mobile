// dart format width=100
// test/features/admin/schedules/admin_schedule_block_lock_test.dart
//
// A day owned by a multi-day plan (`ScheduleBlock`) arrives on the device as an ordinary schedule
// row carrying `isBlockOccupied`, and the backend refuses every write to it
// (`block_occupancy_read_only`) — the same shape as an absence-owned row. Offering any write
// affordance on it invites an edit that can only fail, so every write path the client exposes is
// enumerated here: the admin detail FAB, the admin form (reachable by deep link even when the FAB
// is hidden) and the read-only calendar sheet, which only explains the state.

import 'package:dio/dio.dart';
import 'package:drift/drift.dart' hide isNull;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:mocktail/mocktail.dart';

import 'package:tasktap_mobile/core/widgets/widgets.dart';
import 'package:tasktap_mobile/data/api/dio_client.dart';
import 'package:tasktap_mobile/data/local/app_database.dart';
import 'package:tasktap_mobile/data/sync/connectivity_provider.dart';
import 'package:tasktap_mobile/data/sync/sync_service.dart';
import 'package:tasktap_mobile/features/admin/schedules/admin_schedule_detail_screen.dart';
import 'package:tasktap_mobile/features/admin/schedules/admin_schedule_form_screen.dart';
import 'package:tasktap_mobile/features/calendario/widgets/schedule_info_sheet.dart';

class MockDio extends Mock implements Dio {}

Response<T> _ok<T>(T data, String path) =>
    Response<T>(data: data, statusCode: 200, requestOptions: RequestOptions(path: path));

AppDatabase _makeDb() => AppDatabase(NativeDatabase.memory());

/// One ordinary schedule row. [blockOccupied] is the leaf Task 15 put on the Drift row; it is what
/// the sync now writes from the server's `isBlockOccupied`.
Future<void> _seedSchedule(
  AppDatabase db, {
  String id = 'sched-1',
  bool blockOccupied = false,
}) async {
  await db.into(db.locations).insert(
    LocationsCompanion.insert(
      id: 'loc-1',
      tenantId: 'tenant-1',
      createdAt: DateTime.utc(2026, 1, 1),
      customerId: 'cust-1',
      name: 'Sede Nord',
    ),
  );

  await db.into(db.schedules).insert(
    SchedulesCompanion.insert(
      id: id,
      tenantId: 'tenant-1',
      createdAt: DateTime.utc(2026, 1, 1),
      activityDate: DateTime.utc(2026, 6, 21),
      timeStartMinutes: 480,
      timeEndMinutes: 600,
      userId: 'tech-1',
      statusId: 2,
      locationId: 'loc-1',
      title: 'Manutenzione',
      description: '',
      isBlockOccupied: Value(blockOccupied),
    ),
  );
}

Widget _buildDetail({required AppDatabase db, String scheduleId = 'sched-1'}) {
  return ProviderScope(
    overrides: [appDatabaseProvider.overrideWithValue(db)],
    child: MaterialApp(home: AdminScheduleDetailScreen(scheduleId: scheduleId)),
  );
}

Widget _buildSheet({required AppDatabase db, required Schedule schedule}) {
  return ProviderScope(
    overrides: [appDatabaseProvider.overrideWithValue(db)],
    child: MaterialApp(home: Scaffold(body: ScheduleInfoSheet(schedule: schedule))),
  );
}

void main() {
  setUpAll(() async {
    driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
    registerFallbackValue(RequestOptions(path: '/'));
    await initializeDateFormatting('it', null);
  });

  late AppDatabase db;
  late MockDio mockDio;

  setUp(() {
    db = _makeDb();
    mockDio = MockDio();
  });

  tearDown(() async => db.close());

  Future<Schedule> loadSchedule(String id) async {
    final row = await (db.select(db.schedules)..where((s) => s.id.equals(id))).getSingle();
    return row;
  }

  Future<void> teardown(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
  }

  // ── Admin detail — the edit FAB ─────────────────────────────────────────────

  testWidgets('an occupied day offers no edit affordance', (tester) async {
    await _seedSchedule(db, blockOccupied: true);

    await tester.pumpWidget(_buildDetail(db: db));
    await tester.pumpAndSettle();

    // The absence precedent (`lockedByAbsence`): a locked row hides Modifica instead of letting
    // the office fill a form the server will refuse.
    expect(find.byType(AppFab), findsNothing);
    expect(find.bySemanticsLabel('Modifica'), findsNothing);

    await teardown(tester);
  });

  testWidgets('an occupied day offers no delete affordance', (tester) async {
    await _seedSchedule(db, blockOccupied: true);

    await tester.pumpWidget(_buildDetail(db: db));
    await tester.pumpAndSettle();

    // The shipping client exposes no schedule-delete path at all; this asserts the lock stays true
    // if one is ever added, not that today's build would otherwise offer it.
    expect(find.text('Elimina'), findsNothing);
    expect(find.byTooltip('Elimina'), findsNothing);
    expect(find.byIcon(Icons.delete), findsNothing);

    await teardown(tester);
  });

  testWidgets('the detail says the day belongs to a multi-day plan', (tester) async {
    await _seedSchedule(db, blockOccupied: true);

    await tester.pumpWidget(_buildDetail(db: db));
    await tester.pumpAndSettle();

    // Hiding Modifica without a reason reads as "this one just cannot be edited" — say why, the
    // way the absence banner does.
    expect(find.textContaining('multi-giorno'), findsOneWidget);
    expect(find.textContaining('non si può modificare da qui'), findsOneWidget);

    await teardown(tester);
  });

  testWidgets('an ordinary schedule still offers edit', (tester) async {
    await _seedSchedule(db);

    await tester.pumpWidget(_buildDetail(db: db));
    await tester.pumpAndSettle();

    expect(find.byType(AppFab), findsOneWidget);
    // `AppFab` carries its label as a `Semantics` label, not a `Tooltip` widget.
    expect(tester.widget<AppFab>(find.byType(AppFab)).tooltip, 'Modifica');
    expect(find.textContaining('multi-giorno'), findsNothing);

    await teardown(tester);
  });

  // ── Calendar sheet — read-only, but it should say what the row is ───────────

  testWidgets('the calendar sheet names the multi-day plan', (tester) async {
    await _seedSchedule(db, blockOccupied: true);
    final schedule = await loadSchedule('sched-1');

    await tester.pumpWidget(_buildSheet(db: db, schedule: schedule));
    await tester.pumpAndSettle();

    expect(find.textContaining('multi-giorno'), findsOneWidget);

    await teardown(tester);
  });

  // ── Admin form — deep link / stale navigation ───────────────────────────────

  testWidgets('a form opened for an occupied id refuses to submit', (tester) async {
    await _seedSchedule(db, id: 'sched-block', blockOccupied: true);

    // The form resolves live assignment on open; the read path is not what this test locks.
    when(
      () => mockDio.get<Map<String, dynamic>>(
        '/api/users',
        queryParameters: any(named: 'queryParameters'),
      ),
    ).thenAnswer(
      (_) async => _ok({
        'items': [
          {'id': 'tech-1', 'displayName': 'Mario Rossi'},
        ],
      }, '/api/users'),
    );
    when(() => mockDio.get<Map<String, dynamic>>('/api/schedules/sched-block')).thenAnswer(
      (_) async => _ok({
        'userId': 'tech-1',
        'teamLeadId': 'tech-1',
        'squadraId': null,
        'assignees': [
          {'userId': 'tech-1', 'isDirect': true, 'isLead': true},
        ],
      }, '/api/schedules/sched-block'),
    );
    when(
      () => mockDio.put<dynamic>(
        any(that: contains('/api/schedules/')),
        queryParameters: any(named: 'queryParameters'),
        data: any(named: 'data'),
      ),
    ).thenAnswer((_) async => _ok(null, '/api/schedules/sched-block'));

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          appDatabaseProvider.overrideWithValue(db),
          dioProvider.overrideWithValue(mockDio),
          isOnlineProvider.overrideWithValue(true),
        ],
        child: const MaterialApp(home: AdminScheduleFormScreen(scheduleId: 'sched-block')),
      ),
    );
    await tester.pumpAndSettle();

    // The form states the lock and does not arm the save button — the deep-link path must refuse
    // on its own, because the detail FAB is not the only way in.
    expect(find.textContaining('multi-giorno'), findsOneWidget);

    final submit = find.widgetWithText(AppButton, 'Salva modifiche');
    final scrollable = find.ancestor(
      of: find.text('Assegnazione *'),
      matching: find.byType(Scrollable),
    );
    await tester.scrollUntilVisible(submit, 300, scrollable: scrollable);
    expect(tester.widget<AppButton>(submit).onPressed, isNull);

    await tester.tap(submit);
    await tester.pumpAndSettle();

    verifyNever(
      () => mockDio.put<dynamic>(
        any(that: contains('/api/schedules/')),
        queryParameters: any(named: 'queryParameters'),
        data: any(named: 'data'),
      ),
    );

    await teardown(tester);
  });
}
