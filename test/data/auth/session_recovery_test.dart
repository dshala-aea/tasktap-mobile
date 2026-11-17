// dart format width=100
// SessionRecoveryController — the decision a forced sign-out defers to the next sign-in.
//
// The forced path keeps the data (F1). That is only safe if the NEXT account cannot inherit it:
// same account → send what was kept; different account → ask, explicitly, before any wipe.
import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tasktap_mobile/data/auth/session_recovery.dart';
import 'package:tasktap_mobile/data/auth/unsent_work_counter.dart';
import 'package:tasktap_mobile/data/local/app_database.dart';

const _ownerSub = 'zitadel-sub-owner';
const _otherSub = 'zitadel-sub-someone-else';

void main() {
  late AppDatabase db;
  late SharedPreferences prefs;
  late int discards;

  setUp(() async {
    driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
    db = AppDatabase(NativeDatabase.memory());
    discards = 0;
    SharedPreferences.setMockInitialValues({});
    prefs = await SharedPreferences.getInstance();
    // One pending ticket so the discard prompt has a real count to name.
    await db
        .into(db.pendingTickets)
        .insert(
          PendingTicketsCompanion.insert(
            id: 'ticket-1',
            createdAt: DateTime.utc(2026, 6, 1),
            title: 'Ticket',
            customerId: 'cust-1',
            locationId: 'loc-1',
            statusId: 1,
            typeId: 1,
          ),
        );
  });

  tearDown(() => db.close());

  SessionRecoveryController controller({
    Future<void> Function()? flush,
    Future<SharedPreferences> Function()? prefsLoader,
  }) {
    return SessionRecoveryController(
      counter: UnsentWorkCounter(db: db, countVoiceRecordings: () async => 0),
      discardLocalData: () async => discards++,
      prefsLoader: prefsLoader ?? () async => prefs,
      flushQueues: flush,
    );
  }

  test('no marker: nothing was retained, so nothing is asked', () async {
    var flushes = 0;
    final c = controller(flush: () async => flushes++);

    expect(await c.resolveFor(_ownerSub), isA<SessionRecoveryIdle>());
    expect(flushes, 0);
    expect(await db.select(db.pendingTickets).get(), hasLength(1));
  });

  test('the same account returns: marker cleared, queues flushed, data kept', () async {
    await prefs.setString(sessionRetainedOwnerSubKey, _ownerSub);
    await prefs.setString(sessionRetainedOwnerInternalIdKey, 'internal-1');
    var flushes = 0;
    final c = controller(flush: () async => flushes++);

    final state = await c.resolveFor(_ownerSub);
    // Flush is fire-and-forget so navigation is not held by a week-long backlog.
    await Future<void>.delayed(Duration.zero);

    expect(state, isA<SessionRecoveryIdle>());
    expect(flushes, 1);
    expect(prefs.getString(sessionRetainedOwnerSubKey), isNull);
    expect(prefs.getString(sessionRetainedOwnerInternalIdKey), isNull);
    expect(await db.select(db.pendingTickets).get(), hasLength(1));
    expect(discards, 0);
  });

  test('a DIFFERENT account signs in: the discard is asked, never performed silently', () async {
    await prefs.setString(sessionRetainedOwnerSubKey, _ownerSub);
    final c = controller();

    final state = await c.resolveFor(_otherSub);

    expect(state, const SessionRecoveryNeedsDiscard(1));
    expect(discards, 0, reason: 'the wipe happens only after the screen confirms');
    expect(await db.select(db.pendingTickets).get(), hasLength(1));
    expect(prefs.getString(sessionRetainedOwnerSubKey), _ownerSub);
  });

  test('discard() performs the consented wipe and returns to idle', () async {
    await prefs.setString(sessionRetainedOwnerSubKey, _ownerSub);
    final c = controller();
    await c.resolveFor(_otherSub);

    await c.discard();

    expect(c.state, isA<SessionRecoveryIdle>());
    expect(discards, 1);
  });

  test('the answer is cached per account: the router redirects many times per frame', () async {
    await prefs.setString(sessionRetainedOwnerSubKey, _ownerSub);
    var counts = 0;
    final c = SessionRecoveryController(
      counter: _CountingCounter(db: db, onCount: () => counts++),
      discardLocalData: () async => discards++,
      prefsLoader: () async => prefs,
    );

    await c.resolveFor(_otherSub);
    await c.resolveFor(_otherSub);
    await c.resolveFor(_otherSub);

    expect(counts, 1);
  });

  test('an unreadable prefs store fails OPEN: sign-in is not blocked', () async {
    final c = controller(prefsLoader: () async => throw StateError('storage unavailable'));

    expect(await c.resolveFor(_ownerSub), isA<SessionRecoveryIdle>());
    expect(discards, 0);
  });
}

/// Counts how many times the expensive read actually runs.
class _CountingCounter extends UnsentWorkCounter {
  _CountingCounter({required super.db, required this.onCount})
    : super(countVoiceRecordings: () async => 0);

  final void Function() onCount;

  @override
  Future<UnsentWorkBreakdown> count() async {
    onCount();
    return const UnsentWorkBreakdown(pendingTickets: 2);
  }
}
