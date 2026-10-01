import 'dart:io';

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tasktap_mobile/data/local/app_database.dart';

/// Schema 34 -> 35: `draft_reports.diagnosi` / `soluzione`.
///
/// There is no drift_dev schema-dump tooling in this repo, so the v34 shape is reproduced by
/// creating the current schema in a file database, then dropping the two new columns and
/// rewinding `user_version` to 34 in the `setup` hook of the next connection. Drift then runs the
/// real `onUpgrade(34 -> 35)` against a table that really lacks the columns, with a pre-existing
/// row to prove the migration keeps data.
void main() {
  late Directory dir;
  late File file;

  setUp(() {
    dir = Directory.systemTemp.createTempSync('tasktap_mig35_');
    file = File('${dir.path}/app.sqlite');
  });

  tearDown(() {
    if (dir.existsSync()) dir.deleteSync(recursive: true);
  });

  test('v34 -> v35 adds nullable diagnosi/soluzione and keeps existing rows', () async {
    final fresh = AppDatabase(NativeDatabase(file));
    await fresh
        .into(fresh.draftReports)
        .insert(
          DraftReportsCompanion.insert(
            id: 'r-old',
            tenantId: 't1',
            createdAt: DateTime.utc(2026, 9, 1),
            title: 'Vecchio rapportino',
            insertedUserId: 'u1',
            locationId: 'l1',
          ),
        );
    await fresh.close();

    final v34 = AppDatabase(
      NativeDatabase(
        file,
        setup: (raw) {
          raw.execute('ALTER TABLE draft_reports DROP COLUMN diagnosi');
          raw.execute('ALTER TABLE draft_reports DROP COLUMN soluzione');
          raw.execute('PRAGMA user_version = 34');
        },
      ),
    );
    // Opening runs onUpgrade(34, 35).
    final old = await (v34.select(v34.draftReports)..where((r) => r.id.equals('r-old'))).getSingle();
    expect(old.title, 'Vecchio rapportino');
    expect(old.diagnosi, isNull);
    expect(old.soluzione, isNull);

    await v34
        .into(v34.draftReports)
        .insertOnConflictUpdate(
          DraftReportsCompanion(
            id: const Value('r-old'),
            tenantId: const Value('t1'),
            createdAt: Value(DateTime.utc(2026, 9, 1)),
            title: const Value('Vecchio rapportino'),
            insertedUserId: const Value('u1'),
            locationId: const Value('l1'),
            diagnosi: const Value('Guasto al motore'),
            soluzione: const Value(''),
          ),
        );
    final after = await (v34.select(v34.draftReports)..where((r) => r.id.equals('r-old'))).getSingle();
    expect(after.diagnosi, 'Guasto al motore');
    // Empty string is a value (clears server-side), distinct from null.
    expect(after.soluzione, '');
    await v34.close();
  });

  test('schemaVersion is 35', () async {
    final db = AppDatabase(NativeDatabase.memory());
    expect(db.schemaVersion, 35);
    await db.close();
  });
}
