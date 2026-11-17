// dart format width=100
import 'dart:io';

import 'package:drift/drift.dart' show Value, driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tasktap_mobile/data/local/app_database.dart';

/// Schema 38 -> 39: `draft_reports` gains a nullable `expected_version` TEXT column — the report
/// row's version (`xmin` as a decimal string) as this phone last *saw* the server's copy, carried
/// from a server import to `POST /api/reports/submit` (the backend's stale-submit guard).
///
/// A pure ADD COLUMN, and nullable on purpose: every pre-existing row comes out null, which reads
/// as "this draft was never on the server" and makes the submit omit the version so the server skips
/// the check — exactly the pre-guard behaviour. There is deliberately no backfill: the device
/// genuinely does not know those versions, and an invented one would 409 against the real row on
/// every single submit. So the only thing this migration must get right is that it adds the column
/// and drops nothing.
void main() {
  late Directory dir;
  late File file;

  setUp(() {
    driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
    dir = Directory.systemTemp.createTempSync('tasktap_mig39_');
    file = File('${dir.path}/app.sqlite');
  });

  tearDown(() {
    if (dir.existsSync()) dir.deleteSync(recursive: true);
  });

  final createdAt = DateTime.utc(2026, 9, 1, 9);

  /// A v39 (current) database seeded with two draft rows — the shapes that must survive the
  /// reopen-and-migrate below: a local draft in progress, and a synced-down office Bozza.
  Future<void> seedCurrent() async {
    final db = AppDatabase(NativeDatabase(file));
    await db
        .into(db.draftReports)
        .insert(
          DraftReportsCompanion.insert(
            id: 'draft-old',
            tenantId: 'tenant-1',
            createdAt: createdAt,
            title: 'Rapportino in corso',
            insertedUserId: 'user-1',
            locationId: 'loc-1',
            isLocalOnly: const Value(true),
            submissionState: const Value('draft'),
          ),
        );
    await db
        .into(db.draftReports)
        .insert(
          DraftReportsCompanion.insert(
            id: 'draft-synced',
            tenantId: 'tenant-1',
            createdAt: createdAt,
            title: 'Bozza ufficio',
            insertedUserId: 'user-1',
            locationId: 'loc-1',
            stato: const Value('Bozza'),
          ),
        );
    await db.close();
  }

  /// Rewind the file to a *v38* database — drop the column v39 adds, stamp `user_version = 38` —
  /// so the real `onUpgrade(38 -> 39)` runs on reopen. Mirrors `migration_v38_test.dart`'s own
  /// `reopenAsV37`.
  Future<AppDatabase> reopenAsV38() async {
    final reopened = AppDatabase(
      NativeDatabase(
        file,
        setup: (raw) {
          raw.execute('ALTER TABLE draft_reports DROP COLUMN expected_version');
          // The upgrade now continues 38 -> 39 -> 40, so the column the last step adds must be
          // absent too, or the reopen dies on `duplicate column name`. (v40's other half, the
          // `maintenance_templates` table, needs no undo: `createTable` is `IF NOT EXISTS`.)
          raw.execute('ALTER TABLE pending_tickets DROP COLUMN maintenance_template_id');
          // Schema 41 adds the per-instrument notes: absent in a real v38 database.
          raw.execute('ALTER TABLE report_strumenti DROP COLUMN usage_description');
          raw.execute('ALTER TABLE report_strumenti DROP COLUMN outcome');
          raw.execute('PRAGMA user_version = 38');
        },
      ),
    );
    addTearDown(reopened.close);
    // Force the open + migration.
    await (reopened.select(reopened.draftReports)..limit(1)).get();
    return reopened;
  }

  Future<bool> hasColumn(AppDatabase db, String table, String column) async =>
      (await db.customSelect('PRAGMA table_info($table)').get())
          .any((r) => r.read<String>('name') == column);

  test('a v38 database gains expectedVersion, and existing rows survive with it null', () async {
    await seedCurrent();

    final db = await reopenAsV38();

    expect(
      await hasColumn(db, 'draft_reports', 'expected_version'),
      isTrue,
      reason: 'the migration must add the column the submit path reads',
    );

    final rows = await db.select(db.draftReports).get();
    expect(rows.length, 2, reason: 'an ADD COLUMN migration must drop no row');
    final byId = {for (final r in rows) r.id: r};
    expect(
      byId['draft-old']!.expectedVersion,
      isNull,
      reason: 'a draft from before the column existed has no known version — null, guard off, '
          'never an invented value that would 409 on every submit',
    );
    expect(byId['draft-synced']!.expectedVersion, isNull);
    // The rows' own data is untouched by the migration.
    expect(byId['draft-old']!.title, 'Rapportino in corso');
    expect(byId['draft-old']!.isLocalOnly, isTrue);
    expect(byId['draft-old']!.submissionState, 'draft');
    expect(byId['draft-synced']!.stato, 'Bozza');
  });

  test('a version written at v39 round-trips through the column', () async {
    final db = AppDatabase(NativeDatabase(file));
    await db
        .into(db.draftReports)
        .insert(
          DraftReportsCompanion.insert(
            id: 'draft-imported',
            tenantId: 'tenant-1',
            createdAt: createdAt,
            title: 'Importato',
            insertedUserId: 'user-1',
            locationId: 'loc-1',
            expectedVersion: const Value('4321'),
          ),
        );
    final row = await (db.select(db.draftReports)
          ..where((r) => r.id.equals('draft-imported')))
        .getSingle();
    expect(row.expectedVersion, '4321');
    await db.close();
  });

  test('schemaVersion has not gone backwards', () async {
    final db = AppDatabase(NativeDatabase.memory());
    expect(db.schemaVersion, greaterThanOrEqualTo(39));
    await db.close();
  });
}
