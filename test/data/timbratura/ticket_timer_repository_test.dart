// Unit tests for TicketTimerRepository — the offline half of the ticket timer.
//
// Uses an in-memory NativeDatabase, no file system, no network. The clock is injected so the
// Rome-local frame (workDate + time of day) can be asserted exactly: what is stored here is what
// every ticket worklog reader displays.

import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tasktap_mobile/core/time/business_time.dart';
import 'package:tasktap_mobile/data/local/app_database.dart';
import 'package:tasktap_mobile/data/timbratura/ticket_timer_repository.dart';

AppDatabase _makeDb() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  return AppDatabase(NativeDatabase.memory());
}

void main() {
  late AppDatabase db;
  late TicketTimerRepository repo;

  /// 2026-08-16 08:30 UTC is 10:30 in Rome (CEST). Using a summer and a winter instant is what
  /// catches a fixed-offset implementation.
  final summerStart = DateTime.utc(2026, 8, 16, 8, 30);

  setUp(() {
    db = _makeDb();
    repo = TicketTimerRepository(
      db,
      businessTime: BusinessTime.fallback(),
      clock: () => summerStart,
    );
  });

  tearDown(() async => db.close());

  test('start records a pending row in the Rome frame, with the true instant', () async {
    final row = await repo.start(ticketId: 't1', userId: 'u1');

    expect(row.ticketId, 't1');
    expect(row.isPendingSync, isTrue);
    expect(row.clientId, row.id, reason: 'a device-born row is its own idempotency key');
    expect(row.startUtc, summerStart);
    expect(row.workDate, DateTime.utc(2026, 8, 16));
    expect(row.startSeconds, 10 * 3600 + 30 * 60, reason: '10:30 Rome, not 08:30 UTC');
    expect(row.endSeconds, isNull);
    expect(row.endUtc, isNull);
  });

  test('stop closes the open row and marks it for upload', () async {
    final started = await repo.start(ticketId: 't1', userId: 'u1');

    final closed = await repo.stop(
      't1',
      now: summerStart.add(const Duration(hours: 2)),
    );

    expect(closed, isNotNull);
    expect(closed!.id, started.id);
    expect(closed.endUtc, summerStart.add(const Duration(hours: 2)));
    expect(closed.endSeconds, 12 * 3600 + 30 * 60, reason: '12:30 Rome');
    expect(
      closed.isPendingSync,
      isTrue,
      reason: 'the close has to reach the server even though the start already did',
    );
  });

  test('stop leaves an already-closed session alone and returns null', () async {
    await repo.start(ticketId: 't1', userId: 'u1');
    await repo.stop('t1', now: summerStart.add(const Duration(hours: 2)));

    final again = await repo.stop(
      't1',
      now: summerStart.add(const Duration(hours: 5)),
    );

    expect(again, isNull, reason: 'a stopped session is finished work, not a moving target');
    final rows = await repo.forTicket('t1');
    expect(rows.single.endSeconds, 12 * 3600 + 30 * 60);
  });

  test('stop on another ticket does not touch this one', () async {
    await repo.start(ticketId: 't1', userId: 'u1');

    expect(await repo.stop('t2'), isNull);

    final rows = await repo.forTicket('t1');
    expect(rows.single.endSeconds, isNull);
  });

  test('forTicket is newest first and stays scoped to the ticket', () async {
    await repo.start(ticketId: 't1', userId: 'u1');
    await repo.stop('t1', now: summerStart.add(const Duration(hours: 3)));
    await repo.start(ticketId: 't2', userId: 'u1');
    await repo.stop('t2', now: summerStart.add(const Duration(hours: 1)));
    // A later session on t1, still running.
    final later = TicketTimerRepository(
      db,
      businessTime: BusinessTime.fallback(),
      clock: () => summerStart.add(const Duration(days: 1)),
    );
    await later.start(ticketId: 't1', userId: 'u1');

    final rows = await repo.forTicket('t1');

    expect(rows, hasLength(2));
    expect(rows.first.workDate, DateTime.utc(2026, 8, 17));
    expect(rows[1].workDate, DateTime.utc(2026, 8, 16));
  });

  test('pending is the unsynced backlog, day-agnostic', () async {
    final yesterday = TicketTimerRepository(
      db,
      businessTime: BusinessTime.fallback(),
      clock: () => summerStart.subtract(const Duration(days: 1)),
    );
    await yesterday.start(ticketId: 't1', userId: 'u1');
    await repo.start(ticketId: 't2', userId: 'u1');

    final pending = await repo.pending();

    expect(pending, hasLength(2), reason: 'a backlog is not scoped to today');
    expect(pending.first.workDate, DateTime.utc(2026, 8, 15), reason: 'oldest first');
  });

  test('markSynced adopts the server id and drops the placeholder row', () async {
    final started = await repo.start(ticketId: 't1', userId: 'u1');
    await repo.stop('t1', now: summerStart.add(const Duration(hours: 2)));

    await repo.markSynced(started.clientId!, 'server-1');

    final rows = await repo.forTicket('t1');
    expect(rows, hasLength(1), reason: 'one row per session, not a local twin beside the server one');
    expect(rows.single.id, 'server-1');
    expect(rows.single.clientId, started.clientId);
    expect(rows.single.isPendingSync, isFalse);
    expect(rows.single.startUtc, summerStart);
    expect(rows.single.endUtc, summerStart.add(const Duration(hours: 2)));
    expect(await repo.pending(), isEmpty);
  });

  test('markSynced on an id the server already matched only clears the flag', () async {
    final started = await repo.start(ticketId: 't1', userId: 'u1');

    await repo.markSynced(started.clientId!, started.id);

    final rows = await repo.forTicket('t1');
    expect(rows.single.id, started.id);
    expect(rows.single.isPendingSync, isFalse);
  });

  test('markSyncError holds a row without discarding it', () async {
    final started = await repo.start(ticketId: 't1', userId: 'u1');

    await repo.markSyncError(started.id, 'ticket inesistente');

    final rows = await repo.forTicket('t1');
    expect(rows.single.syncError, 'ticket inesistente');
    expect(rows.single.isPendingSync, isTrue);
  });

  test('running reports the open session, including one started on this device', () async {
    expect(await repo.running(), isNull);
    await repo.start(ticketId: 't1', userId: 'u1');
    await repo.start(ticketId: 't2', userId: 'u1');

    final running = await repo.running();

    expect(running, isNotNull);
    expect(running!.endSeconds, isNull);
  });
}
