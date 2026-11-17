// dart format width=100
// WorkLogReconciler against a shift that opened before midnight.
//
// `getTodaySessions()` is the business-day window. The shift verdict the punch control draws from
// (`actionableShiftStateProvider`) is derived from the WHOLE log, and the reconciler must judge on
// that same horizon — otherwise at 00:10 it sees an empty local day while the Timbra panel still
// draws FINE TURNO for a shift the server closed elsewhere, and the first tap writes a stray fine.
//
// The one judgement that must NOT widen is the local-unsynced guard: `_syncOnce` holds a refused
// day with `isPendingSync = true` until the server accepts it, so a whole-log guard would freeze
// reconciliation for good instead of for one day.
//
// Uses the real Drift repository so the horizons are the real ones.

import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tasktap_mobile/core/time/business_time.dart';
import 'package:tasktap_mobile/data/local/app_database.dart';
import 'package:tasktap_mobile/data/timbratura/work_log_reconciler.dart';
import 'package:tasktap_mobile/data/timbratura/work_session_repository.dart';
import 'package:tasktap_mobile/data/worklogs/active_tracker_api_client.dart';
import 'package:tasktap_mobile/features/timbra/timbra_providers.dart' show deriveShiftState;

void main() {
  late AppDatabase db;
  late WorkSessionRepository repo;

  // The tenant business day the repository windows on (Europe/Rome, live clock).
  final bt = BusinessTime.fallback();

  DateTime todayStart() => bt.todayRangeUtc().$1;

  /// An instant [ago] before now that is nevertheless inside today's business day — a bare
  /// `now - N` lands in the previous one during the first N of the day.
  DateTime earlierToday(Duration ago) {
    final start = todayStart();
    final candidate = DateTime.now().toUtc().subtract(ago);
    return candidate.isAfter(start) ? candidate : start;
  }

  /// The opener of a shift started at 22:00 on the business day before today.
  DateTime lastNightAt2200() => todayStart().subtract(const Duration(hours: 2));

  Future<WorkSession> seed(
    String id,
    String type,
    DateTime time, {
    bool synced = true,
  }) async {
    await repo.addEvent(id: id, eventTime: time, eventType: type);
    if (synced) await repo.markSynced([id]);
    return (await repo.getAllSessions()).firstWhere((s) => s.id == id);
  }

  Future<void> reconcileClosed() =>
      WorkLogReconciler(repo: repo, fetchActive: () async => const <ActiveTracker>[]).reconcile();

  setUp(() {
    driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
    db = AppDatabase(NativeDatabase.memory());
    repo = WorkSessionRepository(db);
  });

  tearDown(() => db.close());

  group('a shift opened before midnight', () {
    test('closed elsewhere: the corrector marks the opener and appends a marked fine', () async {
      await seed('yesterday-i', 'ingresso', lastNightAt2200());
      expect(await repo.getTodaySessions(), isEmpty, reason: 'sanity: the opener is not today');

      await reconcileClosed();

      final all = await repo.getAllSessions();
      expect(all.map((s) => s.eventType), ['ingresso', 'fine']);
      expect(all.first.notes, reconciledOrphanMarker, reason: 'the stale opener is retired');
      expect(all.last.notes, reconciledOrphanMarker, reason: 'the correction is never pushed');
      expect(deriveShiftState(all).isOnShift, isFalse);
      expect(
        await repo.getTodaySessions(),
        hasLength(1),
        reason: 'the correction belongs to today and must be visible on the Timbra screen',
      );
    });

    test('the unsynced guard stays day-scoped: a stuck event on an earlier day does not block it',
        () async {
      // Held by a permanently refused day (`isPendingSync = true`) — it never ages out.
      await seed('stuck-yesterday', 'ingresso', lastNightAt2200(), synced: false);
      await seed('today-i', 'ingresso', earlierToday(const Duration(minutes: 30)));

      await reconcileClosed();

      final all = await repo.getAllSessions();
      expect(all.firstWhere((s) => s.id == 'stuck-yesterday').notes, isNull);
      final allAfter = all.where((s) => s.id != 'stuck-yesterday').toList();
      expect(allAfter.map((s) => s.eventType), ['ingresso', 'fine']);
      expect(allAfter.first.notes, reconciledOrphanMarker);
      expect(deriveShiftState(all).isOnShift, isFalse);
    });

    test('a pending event on TODAY still freezes the correction', () async {
      await seed('today-i', 'ingresso', earlierToday(const Duration(minutes: 30)), synced: false);

      await reconcileClosed();

      final all = await repo.getAllSessions();
      expect(all, hasLength(1), reason: 'the phone\'s own unsent punch wins');
      expect(all.single.notes, isNull);
      expect(deriveShiftState(all).isOnShift, isTrue);
    });
  });

  group('stale fetch race', () {
    test('a change to an OLDER row during the fetch also makes the answer stale', () async {
      // The before/after signature must be taken over the same horizon the correction acts on;
      // taken over today's rows only, a concurrent change to an earlier day goes undetected.
      await seed('stuck-yesterday', 'ingresso', lastNightAt2200(), synced: false);
      await seed('today-i', 'ingresso', earlierToday(const Duration(minutes: 30)));
      var calls = 0;
      final r = WorkLogReconciler(
        repo: repo,
        fetchActive: () async {
          calls++;
          if (calls == 1) await repo.markSynced(['stuck-yesterday']); // the held day got accepted
          return const <ActiveTracker>[];
        },
      );

      await r.reconcile();

      expect(calls, 2, reason: 'the stale answer was discarded and re-fetched');
      expect(deriveShiftState(await repo.getAllSessions()).isOnShift, isFalse);
    });
  });
}
