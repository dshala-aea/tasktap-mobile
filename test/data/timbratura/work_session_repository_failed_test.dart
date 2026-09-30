// dart format width=100
// Events the server permanently refused (409 active_session_exists) are RETAINED for support under
// a distinct marker, but are invisible to everything that derives state or syncs: they cannot act
// as an opener (not a reconciler marker), are never uploaded, and survive clearToday.
import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tasktap_mobile/data/local/app_database.dart';
import 'package:tasktap_mobile/data/timbratura/work_session_repository.dart';

void main() {
  late AppDatabase db;
  late WorkSessionRepository repo;
  setUp(() {
    driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
    db = AppDatabase(NativeDatabase.memory());
    repo = WorkSessionRepository(db);
  });
  tearDown(() => db.close());

  test('markSyncFailed keeps the row, uses its own marker and stops it being pending', () async {
    await repo.addEvent(id: 'a', eventTime: DateTime.now().toUtc(), eventType: 'ingresso');
    await repo.markSyncFailed('a');

    final row = await (db.select(db.workSessions)..where((s) => s.id.equals('a'))).getSingle();
    expect(row.notes, syncFailedMarker);
    expect(syncFailedMarker, isNot(reconciledOrphanMarker));
    expect(row.isPendingSync, isFalse);
  });

  test('failed events are hidden from today\'s view (so they cannot open or close a shift)', () async {
    await repo.addEvent(id: 'a', eventTime: DateTime.now().toUtc(), eventType: 'ingresso');
    await repo.addEvent(id: 'b', eventTime: DateTime.now().toUtc(), eventType: 'fine');
    await repo.markSyncFailed('a');

    expect((await repo.getTodaySessions()).map((s) => s.id), ['b']);
    expect((await repo.watchTodaySessions().first).map((s) => s.id), ['b']);
  });

  test('clearToday does not delete failed events', () async {
    await repo.addEvent(id: 'a', eventTime: DateTime.now().toUtc(), eventType: 'ingresso');
    await repo.addEvent(id: 'b', eventTime: DateTime.now().toUtc(), eventType: 'fine');
    await repo.markSyncFailed('a');
    await repo.clearToday();

    final all = await db.select(db.workSessions).get();
    expect(all.map((s) => s.id), ['a']);
  });
}
