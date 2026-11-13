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
import 'package:drift/drift.dart' hide isNotNull, isNull;
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

Response<T> _ok<T>(T data, String path) => Response<T>(
  data: data,
  statusCode: 200,
  requestOptions: RequestOptions(path: path),
);

AppDatabase _makeDb() => AppDatabase(NativeDatabase.memory());

/// One ordinary schedule row. [blockOccupied] is the leaf Task 15 put on the Drift row; it is what
/// the sync now writes from the server's `isBlockOccupied`. [assenza] is the older, analogous
/// server-owned row: an approved absence is mirrored as a schedule the backend refuses to edit.
Future<void> _seedSchedule(
  AppDatabase db, {
  String id = 'sched-1',
  bool blockOccupied = false,
  bool assenza = false,
}) async {
  await db
      .into(db.locations)
      .insert(
        LocationsCompanion.insert(
          id: 'loc-1',
          tenantId: 'tenant-1',
          createdAt: DateTime.utc(2026, 1, 1),
          customerId: 'cust-1',
          name: 'Sede Nord',
        ),
      );

  await db
      .into(db.schedules)
      .insert(
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
          isAssenza: Value(assenza),
          isBlockOccupied: Value(blockOccupied),
        ),
      );
}

Widget _buildDetail({required AppDatabase db, String scheduleId = 'sched-1'}) {
  return ProviderScope(retry: (_, _) => null, 
    overrides: [appDatabaseProvider.overrideWithValue(db)],
    child: MaterialApp(home: AdminScheduleDetailScreen(scheduleId: scheduleId)),
  );
}

Widget _buildSheet({required AppDatabase db, required Schedule schedule}) {
  return ProviderScope(retry: (_, _) => null, 
    overrides: [appDatabaseProvider.overrideWithValue(db)],
    child: MaterialApp(
      home: Scaffold(body: ScheduleInfoSheet(schedule: schedule)),
    ),
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

  // ── Admin form harness ──────────────────────────────────────────────────────

  Widget buildForm({required String scheduleId}) {
    return ProviderScope(retry: (_, _) => null, 
      overrides: [
        appDatabaseProvider.overrideWithValue(db),
        dioProvider.overrideWithValue(mockDio),
        isOnlineProvider.overrideWithValue(true),
      ],
      child: MaterialApp(home: AdminScheduleFormScreen(scheduleId: scheduleId)),
    );
  }

  /// The reads the edit form makes on open: the technician list and the live detail payload that
  /// rebuilds the assignment. Neither is what these tests lock — only the write is.
  void stubFormReads(String id) {
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
    when(() => mockDio.get<Map<String, dynamic>>('/api/schedules/$id')).thenAnswer(
      (_) async => _ok({
        'userId': 'tech-1',
        'teamLeadId': 'tech-1',
        'squadraId': null,
        'assignees': [
          {'userId': 'tech-1', 'isDirect': true, 'isLead': true},
        ],
      }, '/api/schedules/$id'),
    );
  }

  void stubCleanConflictCheck() {
    when(
      () => mockDio.post<Map<String, dynamic>>(
        '/api/schedules/check-conflicts',
        data: any(named: 'data'),
      ),
    ).thenAnswer((_) async => _ok({'hasConflicts': false, 'conflicts': <dynamic>[]}, '/'));
  }

  /// Brings the submit control into view and returns its finder.
  Future<Finder> scrollToSubmit(WidgetTester tester) async {
    final submit = find.widgetWithText(AppButton, 'Salva modifiche');
    final scrollable = find.ancestor(
      of: find.text('Assegnazione *'),
      matching: find.byType(Scrollable),
    );
    await tester.scrollUntilVisible(submit, 300, scrollable: scrollable);
    return submit;
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

  testWidgets('forward guard: an occupied day offers no delete affordance', (tester) async {
    await _seedSchedule(db, blockOccupied: true);

    await tester.pumpWidget(_buildDetail(db: db));
    await tester.pumpAndSettle();

    // Forward guard, NOT a behavioural test of this lock: the shipping client exposes no
    // schedule-delete path at all, so this passes with the whole feature removed. It only pins
    // that a future delete affordance must honour the same rule; it must not be counted as
    // coverage for the read-only lock.
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

    // First frame: the row has not resolved yet, so the FAB must not be offered. It used to flash
    // in here on `valueOrNull?.isBlockOccupied ?? false`, which reads "not locked" while loading.
    expect(find.byType(AppFab), findsNothing);
    await tester.pumpAndSettle();

    // The redesign moved Modifica into the summary hero; there is no FAB on a detail screen
    // whose hero already carries the action.
    expect(find.byType(AppFab), findsNothing);
    expect(
      find.descendant(
        of: find.byKey(const Key('detail-hero-card')),
        matching: find.text('Modifica'),
      ),
      findsOneWidget,
    );
    expect(find.textContaining('multi-giorno'), findsNothing);

    await teardown(tester);
  });

  // ── Calendar sheet — read-only, but it should say what the row is ───────────

  testWidgets('the calendar sheet names the multi-day plan', (tester) async {
    await _seedSchedule(db, blockOccupied: true);
    final schedule = await loadSchedule('sched-1');

    await tester.pumpWidget(_buildSheet(db: db, schedule: schedule));
    await tester.pumpAndSettle();

    // `_InfoLine` uppercases its label, and the value must not repeat the same phrase.
    expect(find.text('PIANO MULTI-GIORNO'), findsOneWidget);
    expect(find.text('Giornata occupata: non si modifica da qui.'), findsOneWidget);

    await teardown(tester);
  });

  // ── Admin form — deep link / stale navigation ───────────────────────────────

  testWidgets('a form opened for an occupied id refuses to submit', (tester) async {
    await _seedSchedule(db, id: 'sched-block', blockOccupied: true);
    stubFormReads('sched-block');
    when(
      () => mockDio.put<dynamic>(
        any(that: contains('/api/schedules/')),
        queryParameters: any(named: 'queryParameters'),
        data: any(named: 'data'),
      ),
    ).thenAnswer((_) async => _ok(null, '/api/schedules/sched-block'));

    await tester.pumpWidget(buildForm(scheduleId: 'sched-block'));
    await tester.pumpAndSettle();

    // The form states the lock and does not arm the save button — the deep-link path must refuse
    // on its own, because the detail FAB is not the only way in.
    expect(find.textContaining('multi-giorno'), findsOneWidget);

    final submit = await scrollToSubmit(tester);
    // `onPressed == null` alone cannot tell a lock from an in-flight save — both disable the
    // control. Pin the reason: the lock banner is on screen, and `_isSaving` is false (it renders
    // its own spinner through `AppButton.isLoading`, which must not be present).
    expect(tester.widget<AppButton>(submit).onPressed, isNull);
    expect(tester.widget<AppButton>(submit).isLoading, isFalse);
    expect(find.byType(CircularProgressIndicator), findsNothing);

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

  testWidgets('a form opened for an absence-owned id refuses with the absence reason', (
    tester,
  ) async {
    await _seedSchedule(db, id: 'sched-absence', assenza: true);
    stubFormReads('sched-absence');

    await tester.pumpWidget(buildForm(scheduleId: 'sched-absence'));
    await tester.pumpAndSettle();

    // The detail screen already hides Modifica for an absence row, but a deep link reaches this
    // form directly: it has to refuse on its own and name the screen that owns the day.
    expect(find.textContaining('Assenza approvata'), findsOneWidget);
    expect(find.textContaining('Ferie e Permessi'), findsOneWidget);

    final submit = await scrollToSubmit(tester);
    expect(tester.widget<AppButton>(submit).onPressed, isNull);
    expect(tester.widget<AppButton>(submit).isLoading, isFalse);

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

  testWidgets('the save control is disabled before the row resolves', (tester) async {
    await _seedSchedule(db);
    stubFormReads('sched-1');

    // Tall enough that the lazy ListView builds the submit button in the very first frame.
    tester.view.physicalSize = const Size(800, 1800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(buildForm(scheduleId: 'sched-1'));

    final submit = find.widgetWithText(AppButton, 'Salva modifiche');
    expect(submit, findsOneWidget);
    // First frame: `_loadSchedule` has not resolved, so nothing may be submitted yet.
    expect(tester.widget<AppButton>(submit).onPressed, isNull);

    await tester.pumpAndSettle();

    // An ordinary row arms the form once it resolves — the gate is load-driven, not a blanket
    // disable that would also break creates and edits of editable days.
    expect(tester.widget<AppButton>(submit).onPressed, isNotNull);

    await teardown(tester);
  });

  testWidgets('a 400 block_occupancy_read_only locks the form and says why', (tester) async {
    // The mirror does not know the flag (a device that synced before the server sent it), so the
    // form opens armed and only discovers the lock from the server's refusal.
    await _seedSchedule(db, id: 'sched-400');
    stubFormReads('sched-400');
    stubCleanConflictCheck();
    when(
      () => mockDio.put<dynamic>(
        any(that: contains('/api/schedules/')),
        queryParameters: any(named: 'queryParameters'),
        data: any(named: 'data'),
      ),
    ).thenThrow(
      DioException(
        requestOptions: RequestOptions(path: '/api/schedules/sched-400'),
        response: Response<Map<String, dynamic>>(
          requestOptions: RequestOptions(path: '/api/schedules/sched-400'),
          statusCode: 400,
          data: {'status': 400, 'code': 'block_occupancy_read_only'},
        ),
      ),
    );

    await tester.pumpWidget(buildForm(scheduleId: 'sched-400'));
    await tester.pumpAndSettle();

    final submit = await scrollToSubmit(tester);
    expect(tester.widget<AppButton>(submit).onPressed, isNotNull);

    await tester.tap(submit);
    await tester.pumpAndSettle();

    // The server names the owner; the form must adopt the locked state and the specific message
    // instead of "Impossibile salvare. Riprova." with the button armed for the same refusal.
    expect(find.byType(InlineAlert), findsOneWidget);
    expect(find.textContaining('Piano multi-giorno'), findsWidgets);
    expect(find.text('Impossibile salvare. Riprova.'), findsNothing);
    expect(tester.widget<AppButton>(submit).onPressed, isNull);
    expect(tester.widget<AppButton>(submit).isLoading, isFalse);

    await teardown(tester);
  });
}
