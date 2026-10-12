// dart format width=100
//
// The civil-date carrier, end to end around the ticket due date: what the outbox stores, what the
// sync reads off the wire, what the queue sends back, and what the repair wizard seeds from the row.
//
// The bug this guards is a *storage* one (`tickets.dueDate`/`pendingTickets.dueDate` used to be Drift
// `DateTimeColumn`s — see their doc comments in `app_database.dart`), so the assertions are about the
// day that survives each hop, not about a rendered string. The file is in the tz-matrix job because a
// naive implementation passes in Europe/Rome and fails under America/Los_Angeles.

import 'package:drift/drift.dart' show Value, driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tasktap_mobile/core/time/business_time.dart';
import 'package:tasktap_mobile/data/local/app_database.dart';
import 'package:tasktap_mobile/data/sync/sync_dto.dart';
import 'package:tasktap_mobile/data/tickets/pending_ticket_repository.dart';
import 'package:tasktap_mobile/data/tickets/pending_ticket_state.dart';
import 'package:tasktap_mobile/features/ticket/new_ticket_form_state.dart';

void main() {
  late AppDatabase db;
  late PendingTicketRepository repo;

  setUp(() {
    driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
    db = AppDatabase(NativeDatabase.memory());
    repo = PendingTicketRepository(db);
  });

  tearDown(() => db.close());

  Future<void> queueRow({
    required String id,
    required DateTime dueDate,
    String title = 'Caldaia',
  }) => repo.insert(
    id: id,
    title: title,
    customerId: 'cust-1',
    locationId: 'loc-1',
    statusId: 1,
    typeId: 1,
    dueDate: dueDate,
    state: PendingTicketState.pendingSync,
  );

  group('the outbox stores the day, not the instant', () {
    test('a UTC carrier and a local carrier for the same day store the same label', () async {
      // The two carriers the app really produces: `parseDateOnly` hands out `DateTime.utc(y, m, d)`
      // (server values, and anything read back out of a column), while `showDatePicker` hands out a
      // *local* midnight. West of UTC the second is the previous day as an instant; east of UTC the
      // first is. Both mean 1 October to a person, and the column has to say so.
      await queueRow(id: 'q-utc', dueDate: DateTime.utc(2026, 10, 1));
      await queueRow(id: 'q-local', dueDate: DateTime(2026, 10, 1));

      final rows = await repo.watchUnresolved().first;
      expect(rows, hasLength(2));
      expect(
        rows.map((r) => r.dueDate).toSet(),
        {'2026-10-01'},
        reason: 'a DateTimeColumn would have stored two different epoch values here, and read the '
            'first of them back as the previous day on this device',
      );
      for (final row in rows) {
        expect(parseDateOnly(row.dueDate), DateTime.utc(2026, 10, 1));
      }
    });

    test('updateFields rewrites the label, and a cleared date clears the column', () async {
      await queueRow(id: 'q-1', dueDate: DateTime.utc(2026, 10, 1));

      await repo.updateFields(
        id: 'q-1',
        title: 'Caldaia',
        customerId: 'cust-1',
        locationId: 'loc-1',
        statusId: 1,
        typeId: 1,
        dueDate: DateTime.utc(2026, 12, 31),
      );
      expect((await repo.getById('q-1'))!.dueDate, '2026-12-31');

      await repo.updateFields(
        id: 'q-1',
        title: 'Caldaia',
        customerId: 'cust-1',
        locationId: 'loc-1',
        statusId: 1,
        typeId: 1,
      );
      expect((await repo.getById('q-1'))!.dueDate, isNull);
    });
  });

  group('the wire', () {
    test('the label becomes the same instant the create path has always sent', () async {
      await queueRow(id: 'q-1', dueDate: DateTime(2026, 10, 1));

      final row = (await repo.getById('q-1'))!;
      // `TicketCreationQueue._attempt` hands `parseDateOnly(row.dueDate)` to `TicketApiClient`, which
      // serialises it with `toIso8601String()`. The backend's `UtcDateTimeConverter` reads an
      // unspecified kind as UTC, so this is the same day it always was — pinned in
      // `ticket_api_client_test.dart` too, from the other end.
      final wire = parseDateOnly(row.dueDate)!.toIso8601String();
      expect(wire, '2026-10-01T00:00:00.000Z');
    });

    test("the server's due date parses back as the day the server named", () {
      // ASP.NET serialises `Ticket.DueDate` (UTC kind) as a `Z` instant; on this device the *previous
      // local day* was what the old parse produced.
      final dto = TicketDto.fromJson({
        'id': 'ticket-1',
        'tenantId': 'tenant-1',
        'createdAt': '2026-06-01T09:00:00Z',
        'title': 'Perdita idrica',
        'customerId': 'cust-1',
        'locationId': 'loc-1',
        'statusId': 1,
        'typeId': 1,
        'dueDate': '2026-10-01T00:00:00Z',
      });

      expect(dto.dueDate, DateTime.utc(2026, 10, 1));
      expect(formatDateOnly(dto.dueDate), '2026-10-01');
    });
  });

  group('the repair wizard', () {
    test('seeds the day out of the row it is repairing', () async {
      await queueRow(id: 'q-1', dueDate: DateTime(2026, 10, 1), title: 'Da riparare');

      final state = NewTicketFormState.fromPendingRow((await repo.getById('q-1'))!);

      expect(state.dueDate, DateTime.utc(2026, 10, 1));
    });

    test('a row that never had a date seeds none', () async {
      await queueRow(id: 'q-2', dueDate: DateTime.utc(2026, 10, 1));
      await (db.update(db.pendingTickets)..where((t) => t.id.equals('q-2'))).write(
        const PendingTicketsCompanion(dueDate: Value(null)),
      );

      expect(NewTicketFormState.fromPendingRow((await repo.getById('q-2'))!).dueDate, isNull);
    });
  });
}
