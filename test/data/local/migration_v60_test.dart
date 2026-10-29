// dart format width=100
import 'dart:io';

import 'package:drift/drift.dart' show Value, Variable, driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tasktap_mobile/data/local/app_database.dart';

/// Schema 59 -> 60: the technician's real work intervals.
///
/// A NEW table, so `createTable` is additive on its own and Drift emits
/// `CREATE TABLE IF NOT EXISTS`, which also keeps the older-schema fixtures working when they
/// rewind `user_version` on a current-schema database.
void main() {
  late Directory dir;
  late File file;

  setUp(() {
    driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
    dir = Directory.systemTemp.createTempSync('tasktap_mig60_');
    file = File('${dir.path}/app.sqlite');
  });

  tearDown(() {
    if (dir.existsSync()) dir.deleteSync(recursive: true);
  });

  Future<bool> hasTable(AppDatabase db, String table) async =>
      (await db
              .customSelect(
                "SELECT name FROM sqlite_master WHERE type = 'table' AND name = ?",
                variables: [Variable.withString(table)],
              )
              .get())
          .isNotEmpty;

  test('a 59 database gains report_staff_segments', () async {
    // A current-schema database rewound to 59 — the device-before-upgrade shape the other
    // migration tests use, and the shape that would die on a table that already exists if the
    // step used a bare CREATE TABLE.
    final db = AppDatabase(NativeDatabase(file));
    await db.customStatement('PRAGMA user_version = 59');
    await db.customStatement('DROP TABLE IF EXISTS report_staff_segments');
    await db.close();

    final upgraded = AppDatabase(NativeDatabase(file));
    expect(await hasTable(upgraded, 'report_staff_segments'), isTrue);
    await upgraded.close();
  });

  test('the new table round-trips a segment, client id included', () async {
    final db = AppDatabase(NativeDatabase(file));
    await db
        .into(db.reportStaffSegments)
        .insert(
          ReportStaffSegmentsCompanion.insert(
            id: 'seg-1',
            tenantId: 't1',
            createdAt: DateTime.utc(2026, 10, 29, 8),
            reportId: 'report-1',
            userId: 'user-1',
            startUtc: DateTime.utc(2026, 10, 29, 7),
            endUtc: DateTime.utc(2026, 10, 29, 9),
            clientId: const Value('seg-1'),
          ),
        );
    final rows = await db.select(db.reportStaffSegments).get();
    // `.toUtc()` on the value, not on the expectation: `dateTime()` decodes local-kinded (the
    // instant is right, the zone flag is not), so a bare equality against a UTC DateTime fails in
    // any non-UTC zone. Same read-back shape as migration_v52/v53's assertions.
    expect(rows.single.startUtc.toUtc(), DateTime.utc(2026, 10, 29, 7));
    expect(rows.single.clientId, 'seg-1');
    await db.close();
  });
}
