// dart format width=100
import 'dart:io';

import 'package:drift/drift.dart' show Value, driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tasktap_mobile/data/local/app_database.dart';

/// Schema 56 -> 57: a report records why the customer did not sign ("Il cliente non può firmare").
///
/// Two plain nullable columns on `draft_reports`, no backfill: every existing row reads "no reason
/// recorded", which is the true statement about a report written before they existed.
///
/// The `addColumn`s are guarded by `PRAGMA table_info` rather than by `from`, like schemas 50, 51,
/// 55 and 56: the older-schema fixtures in test/ rewind `user_version` on the CURRENT schema, which
/// already declares both columns, so an unconditional add would die on `duplicate column name`
/// before the app opens. The first test below exercises the real add path on a database that
/// genuinely lacks them.
void main() {
  late Directory dir;
  late File file;

  setUp(() {
    driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
    dir = Directory.systemTemp.createTempSync('tasktap_mig57_');
    file = File('${dir.path}/app.sqlite');
  });

  tearDown(() {
    if (dir.existsSync()) dir.deleteSync(recursive: true);
  });

  Future<bool> hasColumn(AppDatabase db, String table, String column) async =>
      (await db.customSelect('PRAGMA table_info($table)').get()).any(
        (r) => r.read<String>('name') == column,
      );

  /// A current-schema database holding one draft — the exact shape a technician's device has the
  /// moment before the upgrade.
  Future<void> seedCurrent() async {
    final db = AppDatabase(NativeDatabase(file));
    await db
        .into(db.draftReports)
        .insert(
          DraftReportsCompanion.insert(
            id: 'report-1',
            tenantId: 't1',
            createdAt: DateTime.utc(2026, 10, 24),
            title: 'Intervento',
            insertedUserId: 'user-1',
            locationId: 'loc-1',
            technicianSignatureAllegatoId: const Value('sig-tech-1'),
            isLocalOnly: const Value(true),
          ),
        );
    await db.close();
  }

  /// Rewinds the file to the shape a real v56 database has: neither column exists.
  NativeDatabase rewindToV56() => NativeDatabase(
    file,
    setup: (raw) {
      raw.execute('ALTER TABLE draft_reports DROP COLUMN customer_signature_absence_reason');
      raw.execute('ALTER TABLE draft_reports DROP COLUMN customer_signature_absence_note');
      raw.execute('PRAGMA user_version = 56');
    },
  );

  test('a v56 database gains both absence columns', () async {
    await seedCurrent();

    final db = AppDatabase(rewindToV56());
    addTearDown(db.close);
    await db.select(db.draftReports).get();

    expect(await hasColumn(db, 'draft_reports', 'customer_signature_absence_reason'), isTrue);
    expect(await hasColumn(db, 'draft_reports', 'customer_signature_absence_note'), isTrue);
  });

  test('the existing draft survives the upgrade, with no reason recorded', () async {
    await seedCurrent();

    final db = AppDatabase(rewindToV56());
    addTearDown(db.close);

    final report = await (db.select(
      db.draftReports,
    )..where((r) => r.id.equals('report-1'))).getSingle();

    expect(report.title, 'Intervento', reason: 'an additive migration drops no row');
    expect(report.tenantId, 't1');
    // Null, not a guess: a report written before the column existed has no recorded reason.
    expect(report.customerSignatureAbsenceReason, isNull);
    expect(report.customerSignatureAbsenceNote, isNull);
  });

  test('the reason and note round-trip as the wire int after the migration', () async {
    await seedCurrent();

    final db = AppDatabase(rewindToV56());
    addTearDown(db.close);
    await db.select(db.draftReports).get();

    await (db.update(db.draftReports)..where((r) => r.id.equals('report-1'))).write(
      const DraftReportsCompanion(
        customerSignatureAbsenceReason: Value(2), // Altro
        customerSignatureAbsenceNote: Value('Cliente in ospedale'),
      ),
    );

    final report = await (db.select(
      db.draftReports,
    )..where((r) => r.id.equals('report-1'))).getSingle();
    expect(report.customerSignatureAbsenceReason, 2);
    expect(report.customerSignatureAbsenceNote, 'Cliente in ospedale');
  });

  test('a database that already has both columns does not die on a duplicate add', () async {
    await seedCurrent();

    // user_version rewound to 56 on a schema that already carries the columns: each guard must
    // skip the add instead of failing on `duplicate column name` before the app opens.
    final db = AppDatabase(
      NativeDatabase(file, setup: (raw) => raw.execute('PRAGMA user_version = 56')),
    );
    addTearDown(db.close);

    final report = await (db.select(
      db.draftReports,
    )..where((r) => r.id.equals('report-1'))).getSingle();
    expect(report.title, 'Intervento');
    expect(report.customerSignatureAbsenceReason, isNull);
  });

  test('schemaVersion has not gone backwards', () async {
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    expect(db.schemaVersion, greaterThanOrEqualTo(57));
  });
}
