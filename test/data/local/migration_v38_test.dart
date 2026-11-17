import 'dart:io';

import 'package:drift/drift.dart' show Value, driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tasktap_mobile/data/local/app_database.dart';

/// Schema 37 -> 38: `tickets.due_date` and `pending_tickets.due_date` stop being Drift
/// `DateTimeColumn`s (epoch seconds, read back through a *local*
/// `DateTime.fromMillisecondsSinceEpoch`) and become `yyyy-MM-dd` TEXT civil dates.
///
/// This is the one step in the ladder that rewrites values rather than merely moving or adding them,
/// so a wrong expression here changes data silently instead of failing — the two display fixes
/// downstream cannot recover a day that was already lost in the column.
///
/// A real v37 database holds two shapes of row, and the test carries one of each:
///
///  * SERVER — what the sync wrote from `Ticket.DueDate`, serialized as `…T00:00:00Z`: the epoch of a
///    UTC midnight. Its day is its day in UTC. This is the shape the old code displayed a day early
///    on a device west of UTC, i.e. the bug.
///  * PICKER — what `showDatePicker` returned and the wizard stored verbatim: the epoch of a *local*
///    midnight. Its day is its day in the device's own zone, and the old code displayed it correctly.
///
/// Both must come out as the day they were meant to mean, in **every** device zone. `unixepoch` on its
/// own would drag the picker row back a day anywhere east of UTC — every Italian device, i.e. every
/// device this app actually runs on — and `localtime` on its own would freeze the server row's
/// off-by-one west of UTC. That is why this file is in the tz-matrix job: Europe/Rome passes under
/// either implementation, Pacific/Auckland only under the right one, America/Los_Angeles only under
/// the right one.
/// Columns the ladder adds *after* 37, which a real v37 database therefore does not have.
///
/// `reopenAsV37` fabricates its v37 by opening the *current* schema and rewinding `user_version`, so
/// every `addColumn` step above 37 has to be undone there or the reopen dies on
/// `duplicate column name`. Schema 39's `draft_reports.expected_version` is what broke this test the
/// first time CI ran it. A schema-40 `addColumn` means adding its column here — the failure is loud,
/// not silent, but this list is what keeps it from being a surprise.
///
/// Only `addColumn` steps belong here. A step that rewrites or re-creates a table (schema 38's
/// `alterTable` on `due_date`) is undone by the fixture's own column surgery, below.
///
/// Dropping these columns is only half of reproducing v37: step 38 re-creates both tables from the
/// CURRENT definition, so it puts every one of them back — and its copy reads a column the old table
/// did not have as the column's own name, unless that step names it in `newColumns`. So the shape
/// below pins the value too (see the `maintenance_template_id` assertion), not just the presence.
const _columnsAddedAfter37 = <String, List<String>>{
  'draft_reports': ['expected_version', 'extension_values'],
  'pending_tickets': ['maintenance_template_id'],
  'report_strumenti': ['usage_description', 'outcome'],
  // Schema 46. `tickets` matters beyond shape: step 38 re-creates that table from the CURRENT
  // definition, so an absent `extension_values` is exactly the case its `newColumns` exists for.
  'tickets': ['extension_values'],
  'cantieri': ['extension_values'],
};

void main() {
  late Directory dir;
  late File file;

  setUp(() {
    driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
    dir = Directory.systemTemp.createTempSync('tasktap_mig38_');
    file = File('${dir.path}/app.sqlite');
  });

  tearDown(() {
    if (dir.existsSync()) dir.deleteSync(recursive: true);
  });

  /// The two instants the old column really held, in the zone this test process is running in. The
  /// picker one is deliberately built from a *local* midnight: SQLite's `localtime` reads the OS zone,
  /// so this is the same zone the migration will convert in.
  final serverEpoch = DateTime.utc(2026, 10, 1).millisecondsSinceEpoch ~/ 1000;
  final pickerEpoch = DateTime(2026, 10, 1).millisecondsSinceEpoch ~/ 1000;

  final ticketCreatedAt = DateTime.utc(2026, 6, 1, 9);

  /// A v37 database: both `due_date` columns are put back to INTEGER (dropping the value, so the
  /// rows below are written as the old code would have left them), the columns later steps add are
  /// dropped, the epochs are stamped in, and `user_version` is rewound so the real
  /// `onUpgrade(37 -> 38)` runs on reopen.
  Future<AppDatabase> reopenAsV37() async {
    final reopened = AppDatabase(
      NativeDatabase(
        file,
        setup: (raw) {
          for (final t in ['tickets', 'pending_tickets']) {
            raw.execute('ALTER TABLE $t DROP COLUMN due_date');
            raw.execute('ALTER TABLE $t ADD COLUMN due_date INTEGER');
          }
          for (final MapEntry(key: table, value: columns) in _columnsAddedAfter37.entries) {
            for (final column in columns) {
              raw.execute('ALTER TABLE $table DROP COLUMN $column');
            }
          }
          raw.execute("UPDATE tickets SET due_date = $serverEpoch WHERE id = 't-server'");
          raw.execute("UPDATE tickets SET due_date = $pickerEpoch WHERE id = 't-picker'");
          raw.execute("UPDATE pending_tickets SET due_date = $pickerEpoch WHERE id = 'q-picker'");
          raw.execute('PRAGMA user_version = 37');
        },
      ),
    );
    addTearDown(reopened.close);
    // Force the open + migration.
    await (reopened.select(reopened.tickets)..limit(1)).get();
    return reopened;
  }

  Future<void> seedV38() async {
    final db = AppDatabase(NativeDatabase(file));
    await db
        .into(db.tickets)
        .insert(
          TicketsCompanion.insert(
            id: 't-server',
            tenantId: 'tenant-1',
            createdAt: ticketCreatedAt,
            title: 'Server ticket',
            description: const Value('dated by the office'),
            customerId: 'cust-1',
            locationId: 'loc-1',
            statusId: 1,
            typeId: 1,
            priority: const Value('Alta'),
          ),
        );
    await db
        .into(db.tickets)
        .insert(
          TicketsCompanion.insert(
            id: 't-picker',
            tenantId: 'tenant-1',
            createdAt: ticketCreatedAt,
            title: 'Picker ticket',
            customerId: 'cust-1',
            locationId: 'loc-1',
            statusId: 2,
            typeId: 2,
          ),
        );
    await db
        .into(db.tickets)
        .insert(
          TicketsCompanion.insert(
            id: 't-null',
            tenantId: 'tenant-1',
            createdAt: ticketCreatedAt,
            title: 'No due date',
            customerId: 'cust-1',
            locationId: 'loc-1',
            statusId: 1,
            typeId: 1,
          ),
        );
    await db
        .into(db.pendingTickets)
        .insert(
          PendingTicketsCompanion.insert(
            id: 'q-picker',
            title: 'Queued ticket',
            customerId: 'cust-1',
            locationId: 'loc-1',
            statusId: 1,
            typeId: 1,
            createdAt: ticketCreatedAt,
          ),
        );
    await db.close();
  }

  Future<List<String>> columnsOf(AppDatabase db, String table) async =>
      (await db.customSelect('PRAGMA table_info($table)').get())
          .map((r) => r.read<String>('name'))
          .toList();

  Future<String?> columnType(AppDatabase db, String table, String column) async {
    final rows = await db.customSelect('PRAGMA table_info($table)').get();
    return rows.firstWhere((r) => r.read<String>('name') == column).read<String>('type');
  }

  test('a v37 database keeps the day each due date meant, in whatever zone the device is in', () async {
    await seedV38();

    final db = await reopenAsV37();

    final server = await (db.select(db.tickets)..where((t) => t.id.equals('t-server'))).getSingle();
    expect(
      server.dueDate,
      '2026-10-01',
      reason: 'the office dated it 1 October and the wire pinned that as UTC midnight; west of UTC '
          'the old column displayed 30 September, and this is the day the fix has to recover',
    );

    final picker = await (db.select(db.tickets)..where((t) => t.id.equals('t-picker'))).getSingle();
    expect(
      picker.dueDate,
      '2026-10-01',
      reason: 'a date the technician picked on this device, stored as local midnight: taking its UTC '
          'day instead would rewrite 1 October as 30 September on any device east of UTC',
    );

    final none = await (db.select(db.tickets)..where((t) => t.id.equals('t-null'))).getSingle();
    expect(none.dueDate, isNull, reason: 'a ticket with no due date keeps none');

    final queued = await (db.select(db.pendingTickets)..where((t) => t.id.equals('q-picker')))
        .getSingle();
    expect(
      queued.dueDate,
      '2026-10-01',
      reason: 'the outbox row is always picker-shaped — its date goes to the server verbatim',
    );

    // The same re-creation also rebuilds `maintenance_template_id`, which `_columnsAddedAfter37`
    // dropped: a v37 table has no such column. Drift writes the copy from the current definition, so
    // the absent column is read as a bare quoted identifier — and SQLite resolves that to the
    // column's own NAME rather than failing. Without step 38 declaring it as a new column, every
    // queued ticket on a v37 device would come out pinned to a template literally called
    // "maintenance_template_id": a value the server answers with a 400 that carries no `field`, so
    // the create queue can never classify it repairable and it retries forever. A value assertion is
    // the only thing that sees this — `columnsOf` below passes either way.
    expect(
      queued.maintenanceTemplateId,
      isNull,
      reason: 'a v37 device has no template picker, so the rebuilt column must be NULL',
    );

    // The same re-creation also rebuilds `tickets.extension_values` (schema 46), which the fixture
    // dropped to make the reopen a real v37 — it is the first `tickets` column to need step 38's
    // `newColumns`. Same trap, same only-sees-it check: the rebuilt column would otherwise hold the
    // literal string "extension_values", which `decodeExtensionValues` reads as "no values recorded"
    // and would therefore never surface on the "Altri campi" section.
    expect(
      server.extensionValues,
      isNull,
      reason: 'a v37 device has no custom-field values, so the rebuilt column must be NULL',
    );
    // Step 46 puts back the columns a real v37 device lacks on the tables step 38 does not rebuild.
    expect(await columnsOf(db, 'cantieri'), contains('extension_values'));
    expect(await columnsOf(db, 'draft_reports'), contains('extension_values'));

    // The rebuild is a real table re-creation, so everything else has to survive it.
    expect(await columnType(db, 'tickets', 'due_date'), 'TEXT');
    expect(await columnType(db, 'pending_tickets', 'due_date'), 'TEXT');
    expect((await db.select(db.tickets).get()).length, 3, reason: 'no row may be dropped');
    expect(server.title, 'Server ticket');
    expect(server.description, 'dated by the office');
    expect(server.priority, 'Alta');
    expect(server.customerId, 'cust-1');
    expect(server.statusId, 1);
    expect(server.createdAt.isAtSameMomentAs(ticketCreatedAt), isTrue);
    expect(queued.title, 'Queued ticket');
    expect(await columnsOf(db, 'tickets'), contains('tags_json'));
    // `_columnsAddedAfter37` dropped it to make the reopen a real v37; step 39 putting it back is
    // what proves the ladder actually ran rather than the fixture having been v39 all along.
    expect(await columnsOf(db, 'draft_reports'), contains('expected_version'));
  });

  test('schemaVersion has not gone backwards', () async {
    final db = AppDatabase(NativeDatabase.memory());
    expect(db.schemaVersion, greaterThanOrEqualTo(38));
    await db.close();
  });
}
