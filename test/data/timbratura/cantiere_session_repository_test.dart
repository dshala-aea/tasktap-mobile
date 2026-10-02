// Unit tests for CantiereSessionRepository — the Drift-backed implementation of
// ICantiereSessionRepository. Uses an in-memory NativeDatabase, no file system.

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tasktap_mobile/core/time/business_time.dart';
import 'package:tasktap_mobile/data/local/app_database.dart';
import 'package:tasktap_mobile/data/timbratura/cantiere_session_repository.dart';

AppDatabase _makeDb() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  return AppDatabase(NativeDatabase.memory());
}

/// [hour]:00 after the start of the current business (default Rome) day, as a UTC instant.
DateTime _businessTodayAt(int hour) {
  final bt = BusinessTime.fallback();
  return bt.utcRangeForBusinessDate(bt.businessToday()).$1.add(Duration(hours: hour));
}

void main() {
  late AppDatabase db;
  late CantiereSessionRepository repo;

  setUp(() {
    db = _makeDb();
    repo = CantiereSessionRepository(db);
  });

  tearDown(() async => db.close());

  test('getTodayEvents is empty before anything is recorded', () async {
    expect(await repo.getTodayEvents(), isEmpty);
  });

  test('addEvent then getTodayEvents returns the event with its site context', () async {
    final now = DateTime.now().toUtc();
    await repo.addEvent(
      id: 'evt-1',
      eventTime: now,
      eventType: 'ingresso',
      cantiereId: 'cant-1',
      customerId: 'cust-1',
      ticketId: 'tick-1',
      description: 'sostituzione pompa',
      latitude: 45.4654,
      longitude: 9.1859,
    );

    final events = await repo.getTodayEvents();
    expect(events, hasLength(1));
    expect(events.single.eventType, 'ingresso');
    expect(events.single.cantiereId, 'cant-1');
    expect(events.single.customerId, 'cust-1');
    expect(events.single.ticketId, 'tick-1');
    expect(events.single.description, 'sostituzione pompa');
    expect(events.single.latitude, 45.4654);
    expect(events.single.longitude, 9.1859);
    expect(events.single.isPendingSync, isTrue);
  });

  test('watchTodayEvents emits after a write', () async {
    final now = DateTime.now().toUtc();
    final future = repo.watchTodayEvents().firstWhere((list) => list.isNotEmpty);
    await repo.addEvent(id: 'evt-1', eventTime: now, eventType: 'ingresso', cantiereId: 'cant-1');
    final events = await future;
    expect(events, hasLength(1));
  });

  test('markSynced clears isPendingSync for the given ids only', () async {
    // getTodayEvents() buckets by the business (Rome) day, so DateTime.now() + 1h can cross into
    // tomorrow. Anchor to today's own business-day 08:00 instead.
    final now = _businessTodayAt(8);
    await repo.addEvent(id: 'a', eventTime: now, eventType: 'ingresso', cantiereId: 'cant-1');
    await repo.addEvent(
      id: 'b',
      eventTime: now.add(const Duration(hours: 1)),
      eventType: 'uscita',
    );

    await repo.markSynced(['a']);

    final events = await repo.getTodayEvents();
    expect(events.firstWhere((e) => e.id == 'a').isPendingSync, isFalse);
    expect(events.firstWhere((e) => e.id == 'b').isPendingSync, isTrue);
  });

  test('markReconciledOrphan writes the marker into notes', () async {
    final now = DateTime.now().toUtc();
    await repo.addEvent(id: 'a', eventTime: now, eventType: 'ingresso', cantiereId: 'cant-1');

    await repo.markReconciledOrphan('a');

    final events = await repo.getTodayEvents();
    expect(events.single.notes, cantiereReconciledOrphanMarker);
  });

  test('markSyncError records the failure message', () async {
    final now = DateTime.now().toUtc();
    await repo.addEvent(id: 'a', eventTime: now, eventType: 'ingresso', cantiereId: 'cant-1');

    await repo.markSyncError('a', 'Connessione assente');

    final events = await repo.getTodayEvents();
    expect(events.single.syncError, 'Connessione assente');
  });

  test('clearToday removes all of today\'s events', () async {
    final now = DateTime.now().toUtc();
    await repo.addEvent(id: 'a', eventTime: now, eventType: 'ingresso', cantiereId: 'cant-1');
    await repo.addEvent(
      id: 'b',
      eventTime: now.add(const Duration(hours: 4)),
      eventType: 'uscita',
    );

    await repo.clearToday();

    expect(await repo.getTodayEvents(), isEmpty);
  });

  test('events are returned in chronological order', () async {
    // getTodayEvents() buckets by the business (Rome) day, so a fixed literal date is wrong on
    // every day but that one and DateTime.now() + 2h can cross into tomorrow. Anchor to today's
    // own business-day 08:00/10:00 instead.
    final earlier = _businessTodayAt(8);
    final later = _businessTodayAt(10);
    await repo.addEvent(id: 'later', eventTime: later, eventType: 'uscita');
    await repo.addEvent(
      id: 'earlier',
      eventTime: earlier,
      eventType: 'ingresso',
      cantiereId: 'cant-1',
    );

    final events = await repo.getTodayEvents();
    expect(events.map((e) => e.id).toList(), ['earlier', 'later']);
  });
}
