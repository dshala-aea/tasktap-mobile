import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tasktap_mobile/data/local/app_database.dart';
import 'package:tasktap_mobile/data/reports/submit_report_request.dart';

/// Whether a model wrote any of a rapportino has to survive to the record.
///
/// The AI draft endpoint shipped without anything recording that it had been used. A technician
/// generated a draft, kept it, signed it and sent it, and the resulting rapportino was
/// indistinguishable from one written by hand — in the office review, in the PDF, and in a
/// subject access export. `AiCallAuditEvent.Accepted` exists for exactly this and is never
/// written, because AI calls are published to the outbox rather than stored.
///
/// The flag is deliberately one-way. Editing a generated paragraph is still working from a
/// generated paragraph, and a marker that clears on the next keystroke is a marker anyone can
/// remove by typing a character.
void main() {
  late AppDatabase db;

  setUp(() {
    driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
    db = AppDatabase(NativeDatabase.memory());
  });

  tearDown(() => db.close());

  Future<void> insertDraft({required bool aiAssisted}) async {
    await db
        .into(db.draftReports)
        .insert(
          DraftReportsCompanion.insert(
            id: 'draft-1',
            tenantId: 'tenant-1',
            createdAt: DateTime.now(),
            title: 'Manutenzione',
            insertedUserId: 'user-1',
            locationId: 'loc-1',
            isAiAssisted: Value(aiAssisted),
          ),
        );
  }

  test('the flag survives a restart, because it lives on the draft row', () async {
    // The editor state is rebuilt empty on every launch; only the row persists. A flag held in
    // memory would quietly disappear between generating a draft in the morning and submitting it
    // after lunch, and the report would be filed as hand-written.
    await insertDraft(aiAssisted: true);

    final row = await (db.select(db.draftReports)
          ..where((t) => t.id.equals('draft-1')))
        .getSingle();

    expect(row.isAiAssisted, isTrue);
  });

  test('a rapportino nobody used AI on defaults to false', () async {
    await insertDraft(aiAssisted: false);

    final row = await (db.select(db.draftReports)
          ..where((t) => t.id.equals('draft-1')))
        .getSingle();

    expect(row.isAiAssisted, isFalse);
  });

  test('the submit payload carries it, so the server can record it', () {
    // Without this the column exists on both sides and nothing ever writes it — the dead-field
    // pattern this change exists to close.
    const request = SubmitReportRequest(
      id: 'draft-1',
      locationId: 'loc-1',
      title: 'Manutenzione',
      aiAssisted: true,
    );

    expect(request.toJson()['aiAssisted'], isTrue);
  });

  test('the payload states it either way rather than omitting it when false', () {
    // An absent field is indistinguishable from an old client that cannot report provenance.
    // Sending false explicitly is a claim; sending nothing is silence.
    const request = SubmitReportRequest(
      id: 'draft-1',
      locationId: 'loc-1',
      title: 'Manutenzione',
    );

    expect(request.toJson().containsKey('aiAssisted'), isTrue);
    expect(request.toJson()['aiAssisted'], isFalse);
  });
}
