// A ticket clock started with no signal is a real running session, so the dashboard must show it.
//
// The ticket timer has a Drift mirror (O-9); the dashboard used to render only what
// `GET /api/worklog/active` returned, so an offline start was invisible here even though the
// ticket screen was counting it. These tests pin the mirror query and the merge rule that keeps a
// server-reported clock from being drawn twice.

import 'package:drift/drift.dart' show Value, driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tasktap_mobile/data/local/app_database.dart';
import 'package:tasktap_mobile/data/sync/sync_service.dart' show appDatabaseProvider;
import 'package:tasktap_mobile/data/worklogs/active_tracker_api_client.dart';
import 'package:tasktap_mobile/features/dashboard/active_trackers_provider.dart';
import 'package:tasktap_mobile/features/timbra/timbra_providers.dart';

final _start = DateTime.utc(2026, 8, 16, 8, 30);

Future<void> _insertTicket(AppDatabase db, String id, String title) => db
    .into(db.tickets)
    .insertOnConflictUpdate(
      TicketsCompanion.insert(
        id: id,
        tenantId: 't',
        title: title,
        customerId: 'cu1',
        locationId: 'loc1',
        statusId: 1,
        typeId: 1,
        createdAt: DateTime.utc(2026, 8, 16),
      ),
    );

Future<void> _insertTimer(
  AppDatabase db, {
  required String id,
  required String ticketId,
  DateTime? startUtc,
  DateTime? endUtc,
}) => db
    .into(db.ticketTimers)
    .insert(
      TicketTimersCompanion.insert(
        id: id,
        ticketId: ticketId,
        userId: const Value('u1'),
        startUtc: Value(startUtc ?? _start),
        endUtc: Value(endUtc),
      ),
    );

/// Reads [localTicketTimersProvider] once its stream has emitted.
Future<List<ActiveTracker>> _local(AppDatabase db) async {
  final c = ProviderContainer(
    overrides: [
      appDatabaseProvider.overrideWithValue(db),
      // The merge reads this too; the server list is empty unless a test overrides it.
      activeTrackersProvider.overrideWith((ref) => Stream.value(const <ActiveTracker>[])),
      todaySessionsProvider.overrideWith((ref) => Stream.value(const <WorkSession>[])),
    ],
  );
  addTearDown(c.dispose);
  return c.read(localTicketTimersProvider.future);
}

void main() {
  late AppDatabase db;

  setUp(() {
    driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
    db = AppDatabase(NativeDatabase.memory());
  });
  tearDown(() => db.close());

  test('a running ticket timer becomes a tracker carrying the ticket title', () async {
    await _insertTicket(db, 't1', 'Perdita in centrale');
    await _insertTimer(db, id: 'w1', ticketId: 't1');

    final trackers = await _local(db);

    expect(trackers, hasLength(1));
    final tracker = trackers.single;
    expect(tracker.kind, ActiveTrackerKind.ticket);
    expect(tracker.id, 'w1');
    expect(tracker.entityId, 't1');
    expect(tracker.label, 'Perdita in centrale');
    expect(tracker.startedAtUtc, _start);
  });

  test('a closed timer is not running and is not listed', () async {
    await _insertTicket(db, 't1', 'Perdita in centrale');
    await _insertTimer(
      db,
      id: 'w1',
      ticketId: 't1',
      endUtc: _start.add(const Duration(hours: 2)),
    );

    expect(await _local(db), isEmpty);
  });

  test('a row with no start instant is left out rather than drawn at a guessed time', () async {
    await _insertTicket(db, 't1', 'Perdita in centrale');
    await db
        .into(db.ticketTimers)
        .insert(
          TicketTimersCompanion.insert(
            id: 'legacy',
            ticketId: 't1',
            userId: const Value('u1'),
            // A legacy row: only the Rome label frame, no instant.
            workDate: Value(DateTime.utc(2026, 8, 16)),
            startSeconds: const Value(10 * 3600),
          ),
        );

    expect(await _local(db), isEmpty);
  });

  test('the visible list shows an offline ticket clock and never repeats a server one', () async {
    final serverTicket = ActiveTracker(
      kind: ActiveTrackerKind.ticket,
      id: 'server-1',
      startedAtUtc: _start,
      label: 'Perdita in centrale',
      entityId: 't1',
    );
    final localOnly = ActiveTracker(
      kind: ActiveTrackerKind.ticket,
      id: 'w2',
      startedAtUtc: _start,
      label: 'Caldaia bloccata',
      entityId: 't2',
    );

    final c = ProviderContainer(
      overrides: [
        activeTrackersProvider.overrideWith(
          (ref) => Stream.value([serverTicket]),
        ),
        todaySessionsProvider.overrideWith((ref) => Stream.value(const <WorkSession>[])),
        localTicketTimersProvider.overrideWith(
          (ref) => Stream.value([serverTicket, localOnly]),
        ),
        // A site session is covered by visible_trackers_local_cantiere_test.dart; overriding keeps
        // this container off the real Drift database.
        localCantiereTimersProvider.overrideWith((ref) => Stream.value(const <ActiveTracker>[])),
      ],
    );
    addTearDown(c.dispose);
    c.listen(visibleTrackersProvider, (_, _) {});
    await c.read(activeTrackersProvider.future);
    await pumpEventQueue();

    final visible = c
        .read(visibleTrackersProvider)
        .where((t) => t.kind == ActiveTrackerKind.ticket);

    expect(visible.map((t) => t.id), ['server-1', 'w2']);
  });
}
