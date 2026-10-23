// dart format width=100
//
// Widget tests for ActiveTrackerStrip's "Ferma"/"Pausa" buttons on the attendance row.
//
// Bug: `_TrackerRow._run()` wraps `punchNotifierProvider.notifier.punch()`/`togglePause()` in a
// try/catch that only fires on a THROWN exception, the same contract `endCantiere()`/`stopTimer()`
// (the cantiere/ticket branches) actually honor. `PunchNotifier.punch()`/`togglePause()` never
// throw, though — a repo failure is caught internally and parked in the notifier's own `state`
// (AsyncError), which is exactly right for TimbraScreen's `ref.listen`. From `_run`'s point of
// view the call always completes "successfully", so a genuine failure closing the worklog or
// toggling a break from the dashboard is silently swallowed: no toast, nothing thrown, nothing to
// find in any log — see timbra_providers.dart's PunchNotifier for the non-throwing contract.

import 'package:dio/dio.dart';
import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:tasktap_mobile/core/location/location_service.dart';
import 'package:tasktap_mobile/data/api/dio_client.dart';
import 'package:tasktap_mobile/data/local/app_database.dart';
import 'package:tasktap_mobile/data/sync/connectivity_provider.dart';
import 'package:tasktap_mobile/data/sync/sync_service.dart' show appDatabaseProvider;
import 'package:tasktap_mobile/data/timbratura/work_session_repository.dart';
import 'package:tasktap_mobile/data/worklogs/active_tracker_api_client.dart';
import 'package:tasktap_mobile/features/dashboard/active_tracker_strip.dart';
import 'package:tasktap_mobile/features/timbra/timbra_providers.dart';
import 'package:tasktap_mobile/presentation/providers/auth_providers.dart' show internalUserIdProvider;

class MockDio extends Mock implements Dio {}

/// Wraps a real (in-memory Drift-backed) repo and fails on the one event type under test —
/// standing in for whatever can genuinely go wrong writing the local event: full disk, a Drift
/// constraint violation, anything that would legitimately reach `PunchNotifier`'s own catch block.
class _FailingOnEventTypeRepo implements IWorkSessionRepository {
  @override
  Stream<List<WorkSession>> watchSyncFailedSessions({
    Duration within = const Duration(days: 7),
  }) => const Stream<List<WorkSession>>.empty();

  @override
  Future<void> markSyncFailed(String id) async {}

  _FailingOnEventTypeRepo(this._inner, this._failingType);

  final IWorkSessionRepository _inner;
  final String _failingType;

  @override
  Future<void> addEvent({
    required String id,
    required DateTime eventTime,
    required String eventType,
    double? latitude,
    double? longitude,
    double? gpsAccuracyMeters,
  }) async {
    if (eventType == _failingType) {
      throw StateError('simulated write failure ($eventType)');
    }
    await _inner.addEvent(
      id: id,
      eventTime: eventTime,
      eventType: eventType,
      latitude: latitude,
      longitude: longitude,
      gpsAccuracyMeters: gpsAccuracyMeters,
    );
  }

  @override
  Stream<List<WorkSession>> watchTodaySessions() => _inner.watchTodaySessions();

  @override
  Future<List<WorkSession>> getTodaySessions() => _inner.getTodaySessions();

  @override
  Future<List<WorkSession>> getPendingSessions() => _inner.getPendingSessions();

  @override
  Future<int> getPendingCount() => _inner.getPendingCount();

  @override
  Future<void> markSynced(List<String> ids) => _inner.markSynced(ids);

  @override
  Future<void> clearToday() => _inner.clearToday();

  @override
  Future<void> markReconciledOrphan(String id) => _inner.markReconciledOrphan(id);
}

void main() {
  setUpAll(() {
    driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  });

  late AppDatabase db;

  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
  });

  tearDown(() async {
    await db.close();
  });

  /// Seeds an open shift (ingresso) directly through the real repo, then hands back a wrapper
  /// that fails on [failingType] — so `timbraStateProvider` sees a genuinely active shift, and
  /// the one write under test genuinely fails.
  Future<IWorkSessionRepository> seededFailingRepo(String failingType) async {
    final real = WorkSessionRepository(db);
    await real.addEvent(id: 'seed-ingresso', eventTime: DateTime.now().toUtc(), eventType: 'ingresso');
    return _FailingOnEventTypeRepo(real, failingType);
  }

  Widget buildStrip({
    required IWorkSessionRepository repo,
    List<ActiveTracker>? trackers,
    bool online = true,
    Dio? dio,
  }) {
    final mockDio = dio ?? MockDio();
    // The queued ticket-timer push runs unawaited behind every close; stub the batch endpoint so
    // an unstubbed call cannot surface as a test failure unrelated to the behaviour under test.
    when(
      () => mockDio.post<Map<String, dynamic>>(
        '/api/tickets/worklogs/mobile/sessions',
        data: any(named: 'data'),
      ),
    ).thenAnswer((_) async => Response<Map<String, dynamic>>(
      data: {'sessions': <dynamic>[]},
      statusCode: 200,
      requestOptions: RequestOptions(path: '/api/tickets/worklogs/mobile/sessions'),
    ));

    return ProviderScope(
      overrides: [
        workSessionRepositoryProvider.overrideWithValue(repo),
        dioProvider.overrideWithValue(mockDio),
        locationServiceProvider.overrideWithValue(const DisabledLocationService()),
        // The cantiere stop reads the site punch log to decide whether it must close a local
        // interval; without this override the container opens the real on-device database.
        appDatabaseProvider.overrideWithValue(db),
        isOnlineProvider.overrideWithValue(online),
        internalUserIdProvider.overrideWith((ref) async => 'user-1'),
      ],
      child: MaterialApp(
        home: Scaffold(
          body: ActiveTrackerStrip(
            trackers:
                trackers ??
                [
                  ActiveTracker(
                    kind: ActiveTrackerKind.attendance,
                    id: 'local-attendance',
                    startedAtUtc: DateTime.now().toUtc().subtract(const Duration(hours: 1)),
                  ),
                ],
          ),
        ),
      ),
    );
  }

  testWidgets(
    'tapping Ferma surfaces a toast when closing the worklog genuinely fails, instead of '
    'silently doing nothing',
    (tester) async {
      final repo = await seededFailingRepo('fine');
      await tester.pumpWidget(buildStrip(repo: repo));
      await tester.pump();
      await tester.pump();

      expect(find.text('Ferma'), findsOneWidget);
      await tester.tap(find.text('Ferma'));
      // Bounded pumps, not pumpAndSettle — the strip's own clock ticks every second.
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));
      await tester.pump();

      // The write genuinely failed (StateError from the repo). That must be visible somewhere —
      // not swallowed into a state nobody on this screen is listening to.
      expect(find.text('Operazione non riuscita.'), findsOneWidget);

      await tester.pumpWidget(const SizedBox.shrink());
      for (var i = 0; i < 5; i++) {
        await tester.pump(Duration.zero);
      }
    },
  );

  testWidgets(
    'tapping Pausa surfaces a toast when starting a break genuinely fails, instead of '
    'silently doing nothing',
    (tester) async {
      final repo = await seededFailingRepo('pausa');
      await tester.pumpWidget(buildStrip(repo: repo));
      await tester.pump();
      await tester.pump();

      expect(find.text('Pausa'), findsOneWidget);
      await tester.tap(find.text('Pausa'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));
      await tester.pump();

      expect(find.text('Operazione non riuscita.'), findsOneWidget);

      await tester.pumpWidget(const SizedBox.shrink());
      for (var i = 0; i < 5; i++) {
        await tester.pump(Duration.zero);
      }
    },
  );

  testWidgets(
    'Ferma on a site session checked in offline closes the local interval instead of calling the '
    'server, which has no log to end',
    (tester) async {
      final start = DateTime.now().toUtc().subtract(const Duration(hours: 1));
      await db
          .into(db.cantierePunches)
          .insert(
            CantierePunchesCompanion.insert(
              id: 'p1',
              eventTime: start,
              eventType: 'ingresso',
              cantiereId: const Value('c1'),
            ),
          );

      await tester.pumpWidget(
        buildStrip(
          repo: WorkSessionRepository(db),
          trackers: [
            ActiveTracker(
              kind: ActiveTrackerKind.cantiere,
              id: 'p1',
              startedAtUtc: start,
              label: 'Cantiere Via Roma',
              entityId: 'c1',
            ),
          ],
        ),
      );
      await tester.pump();
      await tester.pump();

      await tester.tap(find.text('Ferma'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));
      await tester.pump();

      // The online branch would have hit the unstubbed Dio mock and toasted — that is the bug
      // this path replaces.
      expect(find.text('Operazione non riuscita.'), findsNothing);
      final rows = await db.select(db.cantierePunches).get();
      final uscite = rows.where((r) => r.eventType == 'uscita').toList();
      expect(uscite, hasLength(1));
      expect(uscite.single.isPendingSync, isTrue);

      await tester.pumpWidget(const SizedBox.shrink());
      for (var i = 0; i < 5; i++) {
        await tester.pump(Duration.zero);
      }
    },
  );

  testWidgets('tapping Ferma still works normally and invalidates when the write succeeds', (
    tester,
  ) async {
    final real = WorkSessionRepository(db);
    await real.addEvent(id: 'seed-ingresso', eventTime: DateTime.now().toUtc(), eventType: 'ingresso');

    await tester.pumpWidget(buildStrip(repo: real));
    await tester.pump();
    await tester.pump();

    await tester.tap(find.text('Ferma'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    await tester.pump();

    // No failure toast on the happy path.
    expect(find.text('Operazione non riuscita.'), findsNothing);

    final sessions = await real.getTodaySessions();
    expect(sessions.any((s) => s.eventType == 'fine'), isTrue);

    await tester.pumpWidget(const SizedBox.shrink());
    for (var i = 0; i < 5; i++) {
      await tester.pump(Duration.zero);
    }
  });

  // ── Ticket clock ────────────────────────────────────────────────────────────
  //
  // The ticket branch used to call the API directly, alone among the three kinds: with no signal
  // "Ferma" toasted "Operazione non riuscita" and the clock kept running on screen, while the same
  // tap on the ticket detail screen (which had learned the offline path) queued the close. Both now
  // go through `stopTicketTimer`, so these tests pin the shared rule from this side.

  Future<void> seedTicketTimer({String id = 'tt-1', String ticketId = 'ticket-1'}) async {
    await db
        .into(db.ticketTimers)
        .insert(
          TicketTimersCompanion.insert(
            id: id,
            clientId: Value(id),
            ticketId: ticketId,
            userId: const Value('user-1'),
            workDate: Value(DateTime.utc(2026, 10, 22)),
            startSeconds: const Value(9 * 3600),
            startUtc: Value(DateTime.now().toUtc().subtract(const Duration(hours: 1))),
          ),
        );
  }

  List<ActiveTracker> ticketTrackers() => [
    ActiveTracker(
      kind: ActiveTrackerKind.ticket,
      id: 'tt-1',
      startedAtUtc: DateTime.now().toUtc().subtract(const Duration(hours: 1)),
      label: '#1042 — Caldaia condominio',
      entityId: 'ticket-1',
    ),
  ];

  Future<void> tapFermaAndPump(WidgetTester tester) async {
    await tester.tap(find.text('Ferma'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    await tester.pump();
  }

  Future<void> drain(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox.shrink());
    for (var i = 0; i < 5; i++) {
      await tester.pump(Duration.zero);
    }
  }

  testWidgets('Ferma on a ticket clock with no signal closes the mirror row and says it is queued', (
    tester,
  ) async {
    await seedTicketTimer();
    final mockDio = MockDio();

    await tester.pumpWidget(
      buildStrip(
        repo: WorkSessionRepository(db),
        trackers: ticketTrackers(),
        online: false,
        dio: mockDio,
      ),
    );
    await tester.pump();
    await tester.pump();

    await tapFermaAndPump(tester);

    expect(find.text('Operazione non riuscita.'), findsNothing);
    expect(
      find.text('Fermata registrata: verrà inviata al ritorno della connessione.'),
      findsOneWidget,
    );

    final row = await (db.select(db.ticketTimers)..where((t) => t.id.equals('tt-1'))).getSingle();
    expect(row.endUtc, isNotNull, reason: 'the clock the technician sees must stop');
    expect(row.isPendingSync, isTrue, reason: 'the close still has to reach the server');

    // Nothing was sent: the offline path never touches the network.
    verifyNever(() => mockDio.post<dynamic>('/api/tickets/ticket-1/worklogs/stop'));

    await drain(tester);
  });

  testWidgets('Ferma on a ticket clock online stops on the server and closes the mirror quietly', (
    tester,
  ) async {
    await seedTicketTimer();
    final mockDio = MockDio();
    when(
      () => mockDio.post<dynamic>('/api/tickets/ticket-1/worklogs/stop'),
    ).thenAnswer(
      (_) async => Response<dynamic>(
        data: null,
        statusCode: 200,
        requestOptions: RequestOptions(path: '/api/tickets/ticket-1/worklogs/stop'),
      ),
    );

    await tester.pumpWidget(
      buildStrip(repo: WorkSessionRepository(db), trackers: ticketTrackers(), dio: mockDio),
    );
    await tester.pump();
    await tester.pump();

    await tapFermaAndPump(tester);

    expect(
      find.text('Fermata registrata: verrà inviata al ritorno della connessione.'),
      findsNothing,
    );
    expect(find.text('Operazione non riuscita.'), findsNothing);
    verify(() => mockDio.post<dynamic>('/api/tickets/ticket-1/worklogs/stop')).called(1);

    final row = await (db.select(db.ticketTimers)..where((t) => t.id.equals('tt-1'))).getSingle();
    expect(row.endUtc, isNotNull);

    await drain(tester);
  });

  testWidgets('a refused stop is surfaced, but still ends the clock the technician sees', (
    tester,
  ) async {
    await seedTicketTimer();
    final mockDio = MockDio();
    when(
      () => mockDio.post<dynamic>('/api/tickets/ticket-1/worklogs/stop'),
    ).thenAnswer(
      (_) async => throw DioException(
        requestOptions: RequestOptions(path: '/api/tickets/ticket-1/worklogs/stop'),
        type: DioExceptionType.badResponse,
        response: Response<dynamic>(
          data: 'No active timer for this ticket.',
          statusCode: 400,
          requestOptions: RequestOptions(path: '/api/tickets/ticket-1/worklogs/stop'),
        ),
      ),
    );

    await tester.pumpWidget(
      buildStrip(repo: WorkSessionRepository(db), trackers: ticketTrackers(), dio: mockDio),
    );
    await tester.pump();
    await tester.pump();

    await tapFermaAndPump(tester);

    // The server's own reason reaches the technician…
    expect(find.text('Nessun timer attivo su questo intervento.'), findsOneWidget);

    // …and the row is still closed, because the queued close is what makes the second tap honest.
    final row = await (db.select(db.ticketTimers)..where((t) => t.id.equals('tt-1'))).getSingle();
    expect(row.endUtc, isNotNull);
    expect(row.isPendingSync, isTrue);

    await drain(tester);
  });

  testWidgets('Ferma on a ticket clock with no signal says so when the session is not on the device', (
    tester,
  ) async {
    // The clock was started online and no sync mirrored it (the start endpoint answers 200 with no
    // body, so the row can only arrive through the delta sync). There is nothing to close, and
    // claiming "registrata" would be the worst answer available.
    final mockDio = MockDio();

    await tester.pumpWidget(
      buildStrip(
        repo: WorkSessionRepository(db),
        trackers: ticketTrackers(),
        online: false,
        dio: mockDio,
      ),
    );
    await tester.pump();
    await tester.pump();

    await tapFermaAndPump(tester);

    expect(
      find.text(
        'Senza connessione posso fermare solo un timer avviato da questo telefono con i dati '
        'disponibili. Riprova quando hai segnale.',
      ),
      findsOneWidget,
    );
    expect(
      find.text('Fermata registrata: verrà inviata al ritorno della connessione.'),
      findsNothing,
    );

    final rows = await db.select(db.ticketTimers).get();
    expect(rows, isEmpty);

    await drain(tester);
  });
}
