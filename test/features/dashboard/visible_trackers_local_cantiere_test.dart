// A site session checked into with no signal is a real running session, so the dashboard must show
// it — and its stop control must be able to close it.
//
// `cantiere_punches` is the durable local record of a site check-in, exactly like the ticket timer
// mirror. The dashboard used to read only `GET /api/worklog/active`, so an offline check-in was
// invisible here and could not be stopped from here at all, although it was running and would be
// paid for. These tests pin the pairing rule, the midnight-crossing case a today-scoped query
// cannot see, and the merge rule that keeps one site's session from being drawn twice.

import 'package:drift/drift.dart' show Value, driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tasktap_mobile/data/local/app_database.dart';
import 'package:tasktap_mobile/data/sync/sync_service.dart' show appDatabaseProvider;
import 'package:tasktap_mobile/data/worklogs/active_tracker_api_client.dart';
import 'package:tasktap_mobile/features/dashboard/active_trackers_provider.dart';
import 'package:tasktap_mobile/features/timbra/timbra_providers.dart';

final _start = DateTime.utc(2026, 8, 16, 6, 30);

Future<void> _insertCantiere(AppDatabase db, String id, String name) => db
    .into(db.cantieri)
    .insertOnConflictUpdate(
      CantieriCompanion.insert(
        id: id,
        tenantId: 't',
        createdAt: DateTime.utc(2026, 8, 16),
        name: name,
      ),
    );

Future<void> _punch(
  AppDatabase db, {
  required String id,
  required String type,
  required DateTime at,
  String? cantiereId,
}) => db
    .into(db.cantierePunches)
    .insert(
      CantierePunchesCompanion.insert(
        id: id,
        eventTime: at,
        eventType: type,
        cantiereId: Value(cantiereId),
      ),
    );

/// Reads [localCantiereTimersProvider] once its stream has emitted.
Future<List<ActiveTracker>> _local(AppDatabase db) async {
  final c = ProviderContainer(overrides: [appDatabaseProvider.overrideWithValue(db)]);
  addTearDown(c.dispose);
  return c.read(localCantiereTimersProvider.future);
}

void main() {
  late AppDatabase db;

  setUp(() {
    driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
    db = AppDatabase(NativeDatabase.memory());
  });
  tearDown(() => db.close());

  test('an open check-in becomes a cantiere tracker carrying the site name', () async {
    await _insertCantiere(db, 'c1', 'Cantiere Via Roma');
    await _punch(db, id: 'p1', type: 'ingresso', at: _start, cantiereId: 'c1');

    final trackers = await _local(db);

    expect(trackers, hasLength(1));
    final tracker = trackers.single;
    expect(tracker.kind, ActiveTrackerKind.cantiere);
    expect(tracker.id, 'p1');
    expect(tracker.entityId, 'c1');
    expect(tracker.label, 'Cantiere Via Roma');
    expect(tracker.startedAtUtc, _start);
    expect(tracker.startedAtUtc.isUtc, isTrue);
  });

  test('a closed interval is not running and is not listed', () async {
    await _insertCantiere(db, 'c1', 'Cantiere Via Roma');
    await _punch(db, id: 'p1', type: 'ingresso', at: _start, cantiereId: 'c1');
    await _punch(db, id: 'p2', type: 'uscita', at: _start.add(const Duration(hours: 3)));

    expect(await _local(db), isEmpty);
  });

  test('a check-in from a previous day is still open', () async {
    // The Timbra screen reads today's window; the dashboard must not, or the technician cannot
    // close a night shift that started before midnight.
    await _insertCantiere(db, 'c1', 'Cantiere Notte');
    await _punch(
      db,
      id: 'p1',
      type: 'ingresso',
      at: DateTime.utc(2026, 8, 15, 22),
      cantiereId: 'c1',
    );

    expect((await _local(db)).single.id, 'p1');
  });

  test('the last open check-in wins when several sites were visited', () async {
    await _insertCantiere(db, 'c1', 'Primo');
    await _insertCantiere(db, 'c2', 'Secondo');
    await _punch(db, id: 'p1', type: 'ingresso', at: _start, cantiereId: 'c1');
    await _punch(db, id: 'p2', type: 'uscita', at: _start.add(const Duration(hours: 1)));
    await _punch(
      db,
      id: 'p3',
      type: 'ingresso',
      at: _start.add(const Duration(hours: 2)),
      cantiereId: 'c2',
    );

    final tracker = (await _local(db)).single;
    expect(tracker.entityId, 'c2');
    expect(tracker.label, 'Secondo');
  });

  test('a check-in with no cantiere cannot be labelled or reopened, so it is left out', () async {
    await _punch(db, id: 'p1', type: 'ingresso', at: _start);

    expect(await _local(db), isEmpty);
  });

  test('the visible list shows the local session instead of the server one for that site', () async {
    await _insertCantiere(db, 'c1', 'Cantiere Via Roma');
    await _punch(db, id: 'p-local', type: 'ingresso', at: _start, cantiereId: 'c1');

    final serverCantiere = ActiveTracker(
      kind: ActiveTrackerKind.cantiere,
      id: 'server-1',
      startedAtUtc: _start,
      label: 'Cantiere Via Roma',
      entityId: 'c1',
    );
    final otherSite = ActiveTracker(
      kind: ActiveTrackerKind.cantiere,
      id: 'server-2',
      startedAtUtc: _start,
      label: 'Cantiere Nord',
      entityId: 'c2',
    );

    final c = ProviderContainer(
      overrides: [
        appDatabaseProvider.overrideWithValue(db),
        activeTrackersProvider.overrideWith((ref) => Stream.value([serverCantiere, otherSite])),
        todaySessionsProvider.overrideWith((ref) => Stream.value(const <WorkSession>[])),
        localTicketTimersProvider.overrideWith((ref) => Stream.value(const <ActiveTracker>[])),
      ],
    );
    addTearDown(c.dispose);
    c.listen(visibleTrackersProvider, (_, _) {});
    await c.read(activeTrackersProvider.future);
    await c.read(localCantiereTimersProvider.future);
    await pumpEventQueue();

    final visible = c
        .read(visibleTrackersProvider)
        .where((t) => t.kind == ActiveTrackerKind.cantiere)
        .map((t) => t.id);

    // The local row is the one the stop control can actually close.
    expect(visible, ['server-2', 'p-local']);
  });
}
