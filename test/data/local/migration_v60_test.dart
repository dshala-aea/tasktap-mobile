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

  /// The server binds `clientId` as a nullable Guid, so the fixture uses the shape the app will
  /// actually mint (`const Uuid().v4()`), not an arbitrary string.
  const clientId = '3f6c1a8e-5d2b-4c9f-8a1e-7b4d2c9e0f13';

  Future<bool> hasTable(AppDatabase db, String table) async =>
      (await db
              .customSelect(
                "SELECT name FROM sqlite_master WHERE type = 'table' AND name = ?",
                variables: [Variable.withString(table)],
              )
              .get())
          .isNotEmpty;

  /// The columns an index covers, in index order, as SQLite reports them.
  Future<List<String>> indexColumns(AppDatabase db, String index) async =>
      (await db.customSelect('PRAGMA index_info($index)').get())
          .map((r) => r.read<String>('name'))
          .toList();

  test('a 59 database gains report_staff_segments, its index, and can hold a row', () async {
    // A current-schema database rewound to 59 — the device-before-upgrade shape the other
    // migration tests use, and the shape that would die on a table that already exists if the
    // step used a bare CREATE TABLE. `addTearDown` is registered before the explicit close so a
    // failed statement cannot leave the file open for `tearDown`'s delete on Windows; drift's
    // close is a no-op the second time.
    final before = AppDatabase(NativeDatabase(file));
    addTearDown(before.close);
    await before.customStatement('PRAGMA user_version = 59');
    await before.customStatement('DROP TABLE IF EXISTS report_staff_segments');
    await before.close();

    final upgraded = AppDatabase(NativeDatabase(file));
    addTearDown(upgraded.close);

    expect(await hasTable(upgraded, 'report_staff_segments'), isTrue);

    final indexes = await upgraded.customSelect(
      "SELECT name FROM sqlite_master WHERE type = 'index' AND tbl_name = 'report_staff_segments'",
    ).get();
    expect(
      indexes.map((r) => r.read<String>('name')),
      contains('report_staff_segments_report'),
      reason: 'the editor and the submit payload read per report; without it that is a full scan',
    );
    // The name alone proves nothing: `ON report_staff_segments (id)` creates just as happily, and
    // nothing in this release reads through the index, so a wrong column list would only surface
    // in the editor's first query. Asked of SQLite, like `migration_v53_test.dart`'s index check.
    expect(await indexColumns(upgraded, 'report_staff_segments_report'), [
      'report_id',
      'user_id',
    ]);

    // Through the UPGRADED handle, not a freshly created one: a table that exists but rejects an
    // insert (a constraint, a column Drift typed wrong) would otherwise pass this test.
    await upgraded
        .into(upgraded.reportStaffSegments)
        .insert(
          ReportStaffSegmentsCompanion.insert(
            id: 'seg-upgraded',
            tenantId: 't1',
            createdAt: DateTime.utc(2026, 10, 29, 8),
            reportId: 'report-1',
            userId: 'user-1',
            startUtc: DateTime.utc(2026, 10, 29, 7),
            endUtc: DateTime.utc(2026, 10, 29, 9),
            clientId: const Value(clientId),
          ),
        );
    final row = await upgraded.select(upgraded.reportStaffSegments).getSingle();
    expect(row.reportId, 'report-1');
    expect(row.clientId, clientId);
  });

  test('the new table round-trips a segment, client id included', () async {
    final db = AppDatabase(NativeDatabase(file));
    addTearDown(db.close);
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
            clientId: const Value(clientId),
          ),
        );
    final rows = await db.select(db.reportStaffSegments).get();
    // `.toUtc()` on the value, not on the expectation: `dateTime()` decodes local-kinded (the
    // instant is right, the zone flag is not), so a bare equality against a UTC DateTime fails in
    // any non-UTC zone. Same read-back shape as migration_v52/v53's assertions.
    expect(rows.single.startUtc.toUtc(), DateTime.utc(2026, 10, 29, 7));
    expect(rows.single.clientId, clientId);
  });

  test('schemaVersion has not gone backwards', () {
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    expect(db.schemaVersion, greaterThanOrEqualTo(60));
  });
}
