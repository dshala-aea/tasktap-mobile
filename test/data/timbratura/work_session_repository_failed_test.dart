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

  // The whole-log read is what makes "there is a shift to finish" independent of the business-day
  // window — and it must keep the same exclusions as today's view, or a refused punch would open a
  // shift that nothing can ever close.
  test('the whole-log view spans business days and still hides refused rows', () async {
    final now = DateTime.now().toUtc();
    await repo.addEvent(
      id: 'two-days-ago',
      eventTime: now.subtract(const Duration(days: 2)),
      eventType: 'ingresso',
    );
    await repo.addEvent(id: 'refused', eventTime: now, eventType: 'ingresso');
    await repo.markSyncFailed('refused');

    expect((await repo.getAllSessions()).map((s) => s.id), ['two-days-ago']);
    expect((await repo.watchAllSessions().first).map((s) => s.id), ['two-days-ago']);
  });

  test('clearToday does not delete failed events', () async {
    await repo.addEvent(id: 'a', eventTime: DateTime.now().toUtc(), eventType: 'ingresso');
    await repo.addEvent(id: 'b', eventTime: DateTime.now().toUtc(), eventType: 'fine');
    await repo.markSyncFailed('a');
    await repo.clearToday();

    final all = await db.select(db.workSessions).get();
    expect(all.map((s) => s.id), ['a']);
  });

  // Hidden from the shift is not the same as hidden from the person whose hours they were.
  test('watchSyncFailedSessions lists only refused punches, newest first', () async {
    final now = DateTime.now().toUtc();
    await repo.addEvent(id: 'ok', eventTime: now, eventType: 'fine');
    await repo.addEvent(
      id: 'old',
      eventTime: now.subtract(const Duration(hours: 3)),
      eventType: 'ingresso',
    );
    await repo.addEvent(
      id: 'new',
      eventTime: now.subtract(const Duration(hours: 1)),
      eventType: 'pausa',
    );
    await repo.markSyncFailed('old');
    await repo.markSyncFailed('new');

    final rows = await repo.watchSyncFailedSessions().first;
    expect(rows.map((r) => r.id), ['new', 'old']);
  });

  test('the reconciler marker is not a refusal', () async {
    await repo.addEvent(id: 'a', eventTime: DateTime.now().toUtc(), eventType: 'ingresso');
    await repo.markReconciledOrphan('a');

    expect(await repo.watchSyncFailedSessions().first, isEmpty);
  });

  test('a refusal older than the window drops off the notice', () async {
    final now = DateTime.utc(2026, 10, 23, 9);
    final clockRepo = WorkSessionRepository(db, clock: () => now);
    await clockRepo.addEvent(
      id: 'recent',
      eventTime: now.subtract(const Duration(days: 6)),
      eventType: 'ingresso',
    );
    await clockRepo.addEvent(
      id: 'stale',
      eventTime: now.subtract(const Duration(days: 8)),
      eventType: 'fine',
    );
    await clockRepo.markSyncFailed('recent');
    await clockRepo.markSyncFailed('stale');

    final rows = await clockRepo.watchSyncFailedSessions().first;
    // The stale row is still in the table for support — only the notice stops showing it.
    expect(rows.map((r) => r.id), ['recent']);
    expect(
      (await db.select(db.workSessions).get()).map((s) => s.id),
      containsAll(['recent', 'stale']),
    );
  });
}
