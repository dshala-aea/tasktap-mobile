import 'dart:io';

import 'package:drift/drift.dart' show Value, driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tasktap_mobile/data/local/app_database.dart';

/// Schema 35 -> 36: the asset-checklist / strumenti tables, `report_controlli.note`,
/// `draft_reports.strumenti_prefilled` and `draft_reports.submission_problem_json`.
///
/// Same technique as migration_v35_test.dart: create the current schema in a file database, remove
/// exactly what the step adds, rewind `user_version`, reopen so Drift runs the real
/// `onUpgrade(35 -> 36)` against a database that really lacks the objects, with pre-existing rows.
void main() {
  late Directory dir;
  late File file;

  setUp(() {
    driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
    dir = Directory.systemTemp.createTempSync('tasktap_mig36_');
    file = File('${dir.path}/app.sqlite');
  });

  tearDown(() {
    if (dir.existsSync()) dir.deleteSync(recursive: true);
  });

  const newTables = [
    'control_groups',
    'ticket_controls',
    'ticket_assets',
    'assets',
    'strumenti',
    'report_strumenti',
    'checklist_omitted_tickets',
  ];

  Future<List<String>> master(AppDatabase db, String type) async =>
      (await db.customSelect("SELECT name FROM sqlite_master WHERE type = '$type'").get())
          .map((r) => r.read<String>('name'))
          .toList();

  test('v35 -> v36 creates the tables and indexes, adds the columns and keeps existing rows', () async {
    final fresh = AppDatabase(NativeDatabase(file));
    await fresh.into(fresh.draftReports).insert(
          DraftReportsCompanion.insert(
            id: 'r-old',
            tenantId: 't1',
            createdAt: DateTime.utc(2026, 9, 1),
            title: 'Vecchio rapportino',
            insertedUserId: 'u1',
            locationId: 'l1',
          ),
        );
    await fresh.into(fresh.reportControlli).insert(
          ReportControlliCompanion.insert(
            id: 'ctrl-r-old-c1',
            tenantId: 't1',
            createdAt: DateTime.utc(2026, 9, 1),
            reportId: 'r-old',
            controlId: 'c1',
            boolValue: const Value(false),
          ),
        );
    await fresh.close();

    final v35 = AppDatabase(
      NativeDatabase(
        file,
        setup: (raw) {
          for (final t in newTables) {
            raw.execute('DROP TABLE IF EXISTS $t');
          }
          raw.execute('ALTER TABLE report_controlli DROP COLUMN note');
          raw.execute('ALTER TABLE draft_reports DROP COLUMN strumenti_prefilled');
          raw.execute('ALTER TABLE draft_reports DROP COLUMN submission_problem_json');
          raw.execute('PRAGMA user_version = 35');
        },
      ),
    );

    // Opening runs onUpgrade(35, 36).
    expect(await master(v35, 'table'), containsAll(newTables));
    expect(
      await master(v35, 'index'),
      containsAll(['ticket_controls_ticket', 'ticket_controls_asset', 'report_strumenti_report']),
    );

    final answer = await (v35.select(v35.reportControlli)..where((r) => r.id.equals('ctrl-r-old-c1')))
        .getSingle();
    expect(answer.boolValue, isFalse, reason: 'false is an answer and must survive the upgrade');
    expect(answer.note, isNull);

    final draft = await (v35.select(v35.draftReports)..where((r) => r.id.equals('r-old'))).getSingle();
    expect(draft.title, 'Vecchio rapportino');
    expect(draft.strumentiPrefilled, isFalse);
    expect(draft.submissionProblemJson, isNull);

    // The new tables are usable.
    await v35.into(v35.strumenti).insert(
          StrumentiCompanion.insert(
            id: 's1',
            name: 'Multimetro',
            matricola: 'M-1',
            calibrationExpiry: const Value('2026-12-31'),
          ),
        );
    final s = await (v35.select(v35.strumenti)..where((r) => r.id.equals('s1'))).getSingle();
    expect(s.calibrationExpiry, '2026-12-31', reason: 'a civil date is stored as text, not an instant');
    expect(s.isMine, isFalse);

    final version = await v35.customSelect('PRAGMA user_version').getSingle();
    expect(version.read<int>('user_version'), 36);
    await v35.close();
  });

  test('schemaVersion is 36', () async {
    final db = AppDatabase(NativeDatabase.memory());
    expect(db.schemaVersion, 36);
    await db.close();
  });

  test('wipeAllData clears the checklist tables too (sign-out must not leak another tenant)', () async {
    final db = AppDatabase(NativeDatabase.memory());
    await db.into(db.controlGroups).insert(
          ControlGroupsCompanion.insert(
            id: 'g1',
            maintenanceTemplateVersionId: 'v1',
            name: 'G',
            sortOrder: 0,
          ),
        );
    await db.into(db.ticketControls).insert(
          TicketControlsCompanion.insert(
            id: 'tc1',
            ticketId: 't1',
            templateControlId: 'x',
            controlLineageId: 'l1',
            groupId: 'g1',
            label: 'Pressione',
            type: 'Number',
          ),
        );
    await db.into(db.ticketAssets).insert(
          TicketAssetsCompanion.insert(ticketId: 't1', prodottoAssistenzaId: 'a1'),
        );
    await db.into(db.assets).insert(AssetsCompanion.insert(id: 'a1', name: 'Caldaia'));
    await db.into(db.reportStrumenti).insert(
          ReportStrumentiCompanion.insert(id: 'rs1', reportId: 'r1', name: 'M', matricola: '1'),
        );
    await db.into(db.checklistOmittedTickets).insert(
          ChecklistOmittedTicketsCompanion.insert(ticketId: 't9'),
        );

    await db.wipeAllData();

    expect(await db.select(db.controlGroups).get(), isEmpty);
    expect(await db.select(db.ticketControls).get(), isEmpty);
    expect(await db.select(db.ticketAssets).get(), isEmpty);
    expect(await db.select(db.assets).get(), isEmpty);
    expect(await db.select(db.reportStrumenti).get(), isEmpty);
    expect(await db.select(db.checklistOmittedTickets).get(), isEmpty);
    await db.close();
  });
}
