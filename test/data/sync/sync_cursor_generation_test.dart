import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tasktap_mobile/data/local/app_database.dart';

/// A delta cursor can outlive its own correctness, and this is how a device recovers.
///
/// The server's delta filter compared `UpdatedAt > since` against rows whose `UpdatedAt` is null
/// until someone edits them, so anything created after a device's last sync was invisible to that
/// device permanently. Fixing the server does nothing for a phone whose cursor is already past
/// those rows — it will never ask for them again — and "reinstall the app" is not an instruction
/// to give a technician standing in a plant room.
void main() {
  late AppDatabase db;

  setUp(() {
    driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
    db = AppDatabase(NativeDatabase.memory());
  });

  tearDown(() => db.close());

  test('a cursor written by this build is read back', () async {
    // Drift persists DateTime as local; `SyncService` calls `.toUtc()` on the way out, so the
    // wire value is still UTC. Comparing in local terms here keeps the test about the cursor
    // rather than about Drift's storage convention.
    final at = DateTime(2026, 8, 16, 10, 30);
    await db.setLastSync(at);

    expect(await db.getLastSync(), at);
  });

  test('a cursor from an older generation is ignored, forcing one full sync', () async {
    // What every already-installed device looks like: a row under the pre-generation id.
    await db
        .into(db.syncMeta)
        .insertOnConflictUpdate(
          SyncMetaCompanion.insert(
            id: const Value('default'),
            lastSync: Value(DateTime(2026, 8, 1)),
          ),
        );

    expect(
      await db.getLastSync(),
      isNull,
      reason: 'no cursor means a full sync, which is the only thing that recovers the missed rows',
    );
  });

  test('the stale cursor is cleaned up rather than accumulating one row per release', () async {
    await db
        .into(db.syncMeta)
        .insertOnConflictUpdate(
          SyncMetaCompanion.insert(
            id: const Value('default'),
            lastSync: Value(DateTime(2026, 8, 1)),
          ),
        );

    await db.setLastSync(DateTime(2026, 8, 16));

    final rows = await db.select(db.syncMeta).get();
    expect(rows, hasLength(1));
    expect(rows.single.id, contains(AppDatabase.syncCursorGeneration));
  });

  test('the recovery happens once, not on every sync', () async {
    // The obvious over-correction is a client that never keeps a cursor at all and full-syncs
    // forever, which is worse than the bug on a metered connection in a van.
    await db.setLastSync(DateTime(2026, 8, 16, 10));
    expect(await db.getLastSync(), isNotNull);

    await db.setLastSync(DateTime(2026, 8, 16, 11));
    expect(await db.getLastSync(), DateTime(2026, 8, 16, 11));
  });
}
