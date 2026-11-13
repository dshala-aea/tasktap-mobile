// ignore_for_file: avoid_print
import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:tasktap_mobile/data/local/app_database.dart';
import 'package:tasktap_mobile/data/sync/pending_sync_count_provider.dart';
import 'package:tasktap_mobile/data/sync/sync_service.dart'
    show appDatabaseProvider;
import 'package:tasktap_mobile/data/timbratura/work_session_repository.dart'
    show reconciledOrphanMarker;

AppDatabase _makeDb() => AppDatabase(NativeDatabase.memory());

void main() {
  late AppDatabase db;

  setUp(() => db = _makeDb());
  tearDown(() async => db.close());

  test('counts only queued rows as pending, failed rows separately, draft rows not at all', () async {
    await db
        .into(db.draftReports)
        .insert(
          DraftReportsCompanion.insert(
            id: 'r1',
            tenantId: 't1',
            createdAt: DateTime.now(),
            title: 'x',
            insertedUserId: 'u1',
            locationId: 'l1',
            submissionState: const Value('readyToSubmit'),
          ),
        );
    await db
        .into(db.draftReports)
        .insert(
          DraftReportsCompanion.insert(
            id: 'r2',
            tenantId: 't1',
            createdAt: DateTime.now(),
            title: 'x',
            insertedUserId: 'u1',
            locationId: 'l1',
            submissionState: const Value('draft'), // must NOT count
          ),
        );
    await db
        .into(db.draftReports)
        .insert(
          DraftReportsCompanion.insert(
            id: 'r3',
            tenantId: 't1',
            createdAt: DateTime.now(),
            title: 'x',
            insertedUserId: 'u1',
            locationId: 'l1',
            submissionState: const Value('failed'),
          ),
        );
    await db
        .into(db.pendingTickets)
        .insert(
          PendingTicketsCompanion.insert(
            id: 'p1',
            createdAt: DateTime.now(),
            title: 'x',
            customerId: 'c1',
            locationId: 'l1',
            statusId: 1,
            typeId: 1,
            state: const Value('pendingSync'),
          ),
        );
    // Ticket timer sessions: one queued close waiting for signal, one the server refused, and
    // one the server already confirmed (must not count at all).
    await db
        .into(db.ticketTimers)
        .insert(
          TicketTimersCompanion.insert(
            id: 'tt1',
            ticketId: 'ticket-1',
            startUtc: Value(DateTime.now()),
            isPendingSync: const Value(true),
          ),
        );
    await db
        .into(db.ticketTimers)
        .insert(
          TicketTimersCompanion.insert(
            id: 'tt2',
            ticketId: 'ticket-1',
            startUtc: Value(DateTime.now()),
            isPendingSync: const Value(true),
            syncError: const Value('Intervento non trovato.'),
          ),
        );
    await db
        .into(db.ticketTimers)
        .insert(
          TicketTimersCompanion.insert(
            id: 'tt3',
            ticketId: 'ticket-1',
            startUtc: Value(DateTime.now()),
          ),
        );
    // Personal punches are hours not yet on the server too — the break that never arrives is
    // exactly this row. The reconciler's own corrections are pending by construction but are
    // never pushed, so they must not inflate the count.
    await db
        .into(db.workSessions)
        .insert(
          WorkSessionsCompanion.insert(
            id: 'ws1',
            eventTime: DateTime.now().toUtc(),
            eventType: 'ingresso',
            isPendingSync: const Value(true),
          ),
        );
    await db
        .into(db.workSessions)
        .insert(
          WorkSessionsCompanion.insert(
            id: 'ws2',
            eventTime: DateTime.now().toUtc(),
            eventType: 'ripresa',
            notes: const Value(reconciledOrphanMarker),
            isPendingSync: const Value(true),
          ),
        );

    final container = ProviderContainer(
      retry: (_, _) => null,
      overrides: [appDatabaseProvider.overrideWithValue(db)],
    );
    addTearDown(container.dispose);
    container.listen(pendingSyncCountProvider, (_, _) {});

    container.listen(pendingSyncCountProvider, (_, _) {});
    final result = await container.read(pendingSyncCountProvider.future);

    // r1 (readyToSubmit) + p1 (pendingSync) + tt1 + ws1 (personal punch)
    expect(result.pending, 4);
    expect(result.failed, 2); // r3 + tt2
  });
}
