// dart format width=100
// UnsentWorkCounter — the number the logout dialog names must include EVERY queue, because the
// wipe it warns about takes every table. A queue silently missing from this count is the exact
// failure the audit's F1 describes: "N elementi non inviati" under-reporting what Esci destroys.
import 'package:drift/drift.dart' show Value, driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tasktap_mobile/data/auth/unsent_work_counter.dart';
import 'package:tasktap_mobile/data/local/app_database.dart';
import 'package:tasktap_mobile/data/timbratura/cantiere_session_repository.dart'
    show cantiereReconciledOrphanMarker;
import 'package:tasktap_mobile/data/timbratura/work_session_repository.dart'
    show reconciledOrphanMarker;

Future<void> _draft(
  AppDatabase db,
  String id, {
  required bool localOnly,
  required String submissionState,
}) async {
  await db
      .into(db.draftReports)
      .insert(
        DraftReportsCompanion.insert(
          id: id,
          tenantId: 'tenant-1',
          createdAt: DateTime.utc(2026, 6, 1),
          title: 'Rapportino $id',
          insertedUserId: 'user-1',
          locationId: 'loc-1',
          isLocalOnly: Value(localOnly),
          submissionState: Value(submissionState),
        ),
      );
}

Future<void> _ticket(AppDatabase db, String id, {required String state}) async {
  await db
      .into(db.pendingTickets)
      .insert(
        PendingTicketsCompanion.insert(
          id: id,
          createdAt: DateTime.utc(2026, 6, 1),
          title: 'Ticket $id',
          customerId: 'cust-1',
          locationId: 'loc-1',
          statusId: 1,
          typeId: 1,
          state: Value(state),
        ),
      );
}

Future<void> _attachment(AppDatabase db, String id, {required String state}) async {
  await db
      .into(db.pendingTicketAttachments)
      .insert(
        PendingTicketAttachmentsCompanion.insert(
          id: id,
          createdAt: DateTime.utc(2026, 6, 1),
          ticketId: 'ticket-1',
          localPath: '/tmp/$id.jpg',
          fileName: '$id.jpg',
          contentType: 'image/jpeg',
          sizeBytes: 10,
          state: Value(state),
        ),
      );
}

Future<void> _punch(
  AppDatabase db,
  String id, {
  required DateTime at,
  bool pending = true,
  String? notes,
}) async {
  await db
      .into(db.workSessions)
      .insert(
        WorkSessionsCompanion.insert(
          id: id,
          eventTime: at,
          eventType: 'ingresso',
          isPendingSync: Value(pending),
          notes: Value(notes),
        ),
      );
}

Future<void> _cantiere(
  AppDatabase db,
  String id, {
  required DateTime at,
  bool pending = true,
  String? notes,
}) async {
  await db
      .into(db.cantierePunches)
      .insert(
        CantierePunchesCompanion.insert(
          id: id,
          eventTime: at,
          eventType: 'ingresso',
          isPendingSync: Value(pending),
          notes: Value(notes),
        ),
      );
}

Future<void> _timer(AppDatabase db, String id, {bool pending = true, String? syncError}) async {
  await db
      .into(db.ticketTimers)
      .insert(
        TicketTimersCompanion.insert(
          id: id,
          ticketId: 'ticket-1',
          startUtc: Value(DateTime.utc(2026, 10, 21, 8)),
          isPendingSync: Value(pending),
          syncError: Value(syncError),
        ),
      );
}

void main() {
  late AppDatabase db;

  setUp(() {
    driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
    db = AppDatabase(NativeDatabase.memory());
  });

  tearDown(() => db.close());

  test('counts every queue, on any day, and nothing that is already safe', () async {
    // Rapportini: two locally-authored and unsent, one submitted, one synced-down server row
    // (submissionState left at the column default 'draft' — it must NOT be counted).
    await _draft(db, 'd-draft', localOnly: true, submissionState: 'draft');
    await _draft(db, 'd-ready', localOnly: true, submissionState: 'readyToSubmit');
    await _draft(db, 'd-sent', localOnly: false, submissionState: 'submitted');
    await _draft(db, 'd-server', localOnly: false, submissionState: 'draft');

    // Tickets / attachments: everything but 'submitted' is still on the phone.
    await _ticket(db, 't-pending', state: 'pendingSync');
    await _ticket(db, 't-failed', state: 'failed');
    await _ticket(db, 't-sent', state: 'submitted');
    await _attachment(db, 'a-pending', state: 'pendingSync');
    await _attachment(db, 'a-sent', state: 'submitted');

    // Timbra: pending today, pending TEN DAYS AGO (the any-day clause), synced, and a
    // reconciled orphan that the sync services deliberately never send.
    await _punch(db, 'w-today', at: DateTime.utc(2026, 10, 21, 8));
    await _punch(db, 'w-old', at: DateTime.utc(2026, 10, 11, 8));
    await _punch(db, 'w-synced', at: DateTime.utc(2026, 10, 21, 9), pending: false);
    await _punch(
      db,
      'w-orphan',
      at: DateTime.utc(2026, 10, 21, 10),
      notes: reconciledOrphanMarker,
    );

    // Cantiere: one pending, one synced, one reconciled orphan.
    await _cantiere(db, 'c-pending', at: DateTime.utc(2026, 10, 21, 8));
    await _cantiere(db, 'c-synced', at: DateTime.utc(2026, 10, 21, 9), pending: false);
    await _cantiere(
      db,
      'c-orphan',
      at: DateTime.utc(2026, 10, 21, 10),
      notes: cantiereReconciledOrphanMarker,
    );

    // Ticket timers: a queued start, a queued close the server refused (still on the device, so
    // still at risk), and a session the server has already confirmed.
    await _timer(db, 'tt-pending');
    await _timer(db, 'tt-refused', syncError: 'Intervento non trovato.');
    await _timer(db, 'tt-synced', pending: false);

    final counter = UnsentWorkCounter(db: db, countVoiceRecordings: () async => 3);
    final breakdown = await counter.count();

    expect(breakdown.draftReports, 2);
    expect(breakdown.pendingTickets, 2);
    expect(breakdown.pendingAttachments, 1);
    expect(breakdown.workSessions, 2, reason: 'both days must count; the orphan must not');
    expect(breakdown.cantierePunches, 1);
    expect(breakdown.ticketTimers, 2, reason: 'hours are billable; a refused row is still unsent');
    expect(breakdown.voiceRecordings, 3);
    expect(breakdown.total, 13);
    expect(breakdown.isEmpty, isFalse);
  });

  test('an empty device counts zero and reports empty', () async {
    final counter = UnsentWorkCounter(db: db, countVoiceRecordings: () async => 0);
    final breakdown = await counter.count();

    expect(breakdown.total, 0);
    expect(breakdown.isEmpty, isTrue);
    expect(breakdown.isSingular, isFalse);
  });

  test('the singular form is only for exactly one item', () async {
    await _ticket(db, 't-1', state: 'pendingSync');
    final counter = UnsentWorkCounter(db: db, countVoiceRecordings: () async => 0);

    final one = await counter.count();
    expect(one.total, 1);
    expect(one.isSingular, isTrue);

    await _ticket(db, 't-2', state: 'pendingSync');
    final two = await counter.count();
    expect(two.total, 2);
    expect(two.isSingular, isFalse);
  });
}
