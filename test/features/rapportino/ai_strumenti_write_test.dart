// dart format width=100
// test/features/rapportino/ai_strumenti_write_test.dart
//
// The instruments slice's mobile write: Confirm resolves each id against the tenant and persists
// nothing, so the report's instrument lines are the client's. These tests pin what the writer is
// allowed to do — and the three things it must never do: invent an id, overwrite the technician's
// text, or quietly drop an expired instrument.

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:tasktap_mobile/data/local/app_database.dart';
import 'package:tasktap_mobile/data/reports/draft_report_repository.dart';
import 'package:tasktap_mobile/domain/reports/strumenti_selection.dart' show strumentoRowId;
import 'package:tasktap_mobile/features/rapportino/ai_strumenti_write.dart';

AppDatabase _makeDb() => AppDatabase(NativeDatabase.memory());

const _reportId = 'rep-1';

Future<DraftReportRepository> _repo(AppDatabase db) async {
  final repo = DraftReportRepository(db);
  await repo.createDraft(
    DraftReportsCompanion.insert(
      id: _reportId,
      tenantId: 'tenant-1',
      createdAt: DateTime.utc(2026, 10, 23),
      title: 'Rapportino',
      insertedUserId: 'u-1',
      locationId: '',
    ),
  );
  return repo;
}

void main() {
  late AppDatabase db;
  late DraftReportRepository repo;

  setUp(() async {
    db = _makeDb();
    repo = await _repo(db);
  });
  tearDown(() => db.close());

  test('a resolved line becomes a row the Strumenti step already addresses', () async {
    await writeAiStrumenti(
      repo,
      reportId: _reportId,
      lines: [
        AiStrumentoLine(
          strumentoId: 'st-1',
          name: 'Calibro',
          matricola: 'M-77',
          calibrationExpiry: DateTime.utc(2026, 10, 7),
          usageDescription: 'misura',
          outcome: '25.4 mm',
          knowsExpiry: true,
        ),
      ],
    );

    final row = (await repo.getLocalStrumenti(_reportId)).single;
    expect(row.id, strumentoRowId(_reportId, 'st-1'));
    expect(row.strumentoId, 'st-1');
    expect(row.name, 'Calibro');
    expect(row.matricola, 'M-77');
    expect(row.calibrationExpiry, '2026-10-07');
    expect(row.usageDescription, 'misura');
    expect(row.outcome, '25.4 mm');
    expect(row.isLocal, isTrue);

    final header = await repo.getDraft(_reportId);
    expect(
      header!.strumentiPrefilled,
      isTrue,
      reason: 'otherwise the kit pre-fill would add the whole kit over this selection',
    );
  });

  test('an expired, unacknowledged line is written with the verdict, never dropped', () async {
    await writeAiStrumenti(
      repo,
      reportId: _reportId,
      lines: [
        AiStrumentoLine(
          strumentoId: 'st-2',
          name: 'Manometro',
          expiredAtUse: true,
          expiredAcknowledged: false,
          knowsExpiry: true,
        ),
      ],
    );

    final row = (await repo.getLocalStrumenti(_reportId)).single;
    expect(row.expiredAtUse, isTrue);
    expect(
      row.expiredAcknowledged,
      isFalse,
      reason: 'only the technician may acknowledge; the step asks before the submit',
    );
  });

  test("a later turn does not overwrite what the technician typed", () async {
    await writeAiStrumenti(
      repo,
      reportId: _reportId,
      lines: [
        AiStrumentoLine(
          strumentoId: 'st-1',
          name: 'Calibro',
          expiredAtUse: true,
          expiredAcknowledged: false,
          knowsExpiry: true,
        ),
      ],
    );
    // The technician acknowledges it and writes their own notes in the step.
    await repo.updateLocalStrumentoNotes(
      _reportId,
      'st-1',
      const ReportStrumentiCompanion(
        expiredAcknowledged: Value(true),
        usageDescription: Value('misura del collettore'),
        outcome: Value('ok'),
      ),
    );

    // The next turn says the same instrument, with no notes of its own (the draft carries none).
    await writeAiStrumenti(
      repo,
      reportId: _reportId,
      lines: [AiStrumentoLine(strumentoId: 'st-1', name: 'Calibro')],
    );

    final row = (await repo.getLocalStrumenti(_reportId)).single;
    expect(row.usageDescription, 'misura del collettore');
    expect(row.outcome, 'ok');
    expect(
      row.expiredAcknowledged,
      isTrue,
      reason: 'a draft line knows nothing about expiry and must not undo an acknowledgement',
    );
    expect(row.expiredAtUse, isTrue, reason: 'nor reset the verdict Confirm computed');
  });

  test('an id the model never verified is not written, and duplicates collapse', () async {
    await writeAiStrumenti(
      repo,
      reportId: _reportId,
      lines: [
        // A dictated name no lookup resolved: the technician has to pick it in the step.
        const AiStrumentoLine(strumentoId: '', name: 'una chiave inglese'),
        const AiStrumentoLine(strumentoId: 'st-3', name: 'Livella', matricola: 'L-1'),
        const AiStrumentoLine(strumentoId: 'st-3', name: 'Livella', usageDescription: 'prima'),
      ],
    );

    final rows = await repo.getLocalStrumenti(_reportId);
    expect(rows, hasLength(1));
    expect(rows.single.name, 'Livella');
    expect(rows.single.matricola, 'L-1', reason: 'the first line for an id wins');
  });

  test('a valid line never writes an acknowledgement', () async {
    await writeAiStrumenti(
      repo,
      reportId: _reportId,
      lines: [
        AiStrumentoLine(
          strumentoId: 'st-4',
          name: 'Trapano',
          usageDescription: 'foro',
          knowsExpiry: true,
        ),
      ],
    );

    final row = (await repo.getLocalStrumenti(_reportId)).single;
    expect(row.expiredAcknowledged, isFalse, reason: 'a valid instrument with a true flag is a 422');
  });

  test('nothing resolved writes nothing at all', () async {
    await writeAiStrumenti(
      repo,
      reportId: _reportId,
      lines: const [AiStrumentoLine(strumentoId: '', name: 'x')],
    );

    expect(await repo.getLocalStrumenti(_reportId), isEmpty);
    expect((await repo.getDraft(_reportId))!.strumentiPrefilled, isFalse);
  });
}
