import 'package:drift/drift.dart' show driftRuntimeOptions, Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tasktap_mobile/data/local/app_database.dart';
import 'package:tasktap_mobile/data/reports/draft_report_repository.dart';
import 'package:tasktap_mobile/presentation/providers/report_editor_providers.dart';

/// Insert the draft header a real editor always has (createLocalDraft runs before the screen);
/// without it `_hydrate` treats the state as a hand-built placeholder and loads nothing back.
Future<void> seedDraft(AppDatabase db, String reportId) async {
  await db
      .into(db.draftReports)
      .insert(
        DraftReportsCompanion.insert(
          id: reportId,
          tenantId: 'tenant-1',
          createdAt: DateTime.utc(2026, 10, 7, 9),
          title: 'init',
          insertedUserId: 'u1',
          locationId: '',
          isLocalOnly: const Value(true),
          stato: const Value('Bozza'),
        ),
      );
}

Future<ReportEditorNotifier> editor(AppDatabase db) async {
  final n = ReportEditorNotifier(
    initialState: ReportEditorState(
      reportId: 'r1',
      tenantId: 'tenant-1',
      insertedUserId: 'u1',
      createdAt: DateTime.utc(2026, 10, 7, 9),
    ),
    repo: DraftReportRepository(db),
  );
  await n.ready;
  return n;
}

void main() {
  late AppDatabase db;

  setUp(() {
    driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
    db = AppDatabase(NativeDatabase.memory());
  });
  tearDown(() => db.close());

  test('a note is stored with the answer and survives a restart of the editor', () async {
    await seedDraft(db, 'r1');
    final n = await editor(db);
    await n.upsertControllo(
      const ControlloRow(
        id: 'ctrl-r1-c1', reportId: 'r1', controlId: 'c1', numberValue: 0, note: 'manometro ok',
      ),
    );

    final row = (await db.select(db.reportControlli).get()).single;
    expect((row.numberValue, row.note), (0, 'manometro ok'));

    final reopened = await editor(db);
    final back = reopened.state.controlloRows.single;
    expect((back.controlId, back.numberValue, back.note), ('c1', 0, 'manometro ok'));
  });

  test('a note-only row is a valid local state (the server stores it as a note, not an answer)', () async {
    final n = await editor(db);
    await n.upsertControllo(
      const ControlloRow(id: 'ctrl-r1-c2', reportId: 'r1', controlId: 'c2', note: 'perdita'),
    );
    final row = (await db.select(db.reportControlli).get()).single;
    expect((row.boolValue, row.stringValue, row.numberValue, row.note), (null, null, null, 'perdita'));
  });

  test('removeControllo drops the row from state and from the database', () async {
    final n = await editor(db);
    await n.upsertControllo(
      const ControlloRow(id: 'ctrl-r1-c1', reportId: 'r1', controlId: 'c1', boolValue: true),
    );
    await n.removeControllo('ctrl-r1-c1');
    expect(n.state.controlloRows, isEmpty);
    expect(await db.select(db.reportControlli).get(), isEmpty);
  });

  test('copyWith keeps the note unless told to clear it', () {
    const row = ControlloRow(id: 'i', reportId: 'r', controlId: 'c', note: 'x', boolValue: false);
    expect(row.copyWith(boolValue: true).note, 'x');
    expect(row.copyWith(clearNote: true).note, isNull);
  });
}
