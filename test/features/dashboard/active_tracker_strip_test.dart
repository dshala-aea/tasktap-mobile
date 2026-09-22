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
import 'package:tasktap_mobile/data/timbratura/work_session_repository.dart';
import 'package:tasktap_mobile/data/worklogs/active_tracker_api_client.dart';
import 'package:tasktap_mobile/features/dashboard/active_tracker_strip.dart';
import 'package:tasktap_mobile/features/timbra/timbra_providers.dart';

class MockDio extends Mock implements Dio {}

/// Wraps a real (in-memory Drift-backed) repo and fails on the one event type under test —
/// standing in for whatever can genuinely go wrong writing the local event: full disk, a Drift
/// constraint violation, anything that would legitimately reach `PunchNotifier`'s own catch block.
class _FailingOnEventTypeRepo implements IWorkSessionRepository {
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

  Widget buildStrip({required IWorkSessionRepository repo}) {
    return ProviderScope(
      overrides: [
        workSessionRepositoryProvider.overrideWithValue(repo),
        dioProvider.overrideWithValue(MockDio()),
        locationServiceProvider.overrideWithValue(const DisabledLocationService()),
      ],
      child: MaterialApp(
        home: Scaffold(
          body: ActiveTrackerStrip(
            trackers: [
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
}
