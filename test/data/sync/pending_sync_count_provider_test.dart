// ignore_for_file: avoid_print
import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:tasktap_mobile/data/local/app_database.dart';
import 'package:tasktap_mobile/data/sync/pending_sync_count_provider.dart';
import 'package:tasktap_mobile/data/sync/sync_service.dart'
    show appDatabaseProvider;

AppDatabase _makeDb() => AppDatabase(NativeDatabase.memory());

void main() {
  late AppDatabase db;

  setUp(() => db = _makeDb());
  tearDown(() async => db.close());

  test(
    'counts only queued rows as pending, failed rows separately, draft rows not at all',
    () async {
      await db
          .into(db.draftReports)
          .insert(
            DraftReportsCompanion.insert(
              id: 'r1',
              tenantId: 't1',
              createdAt: DateTime.now(),
              title: 'x',
              insertedUserId: 'u1',
              locationId: 'l1',
              submissionState: const Value('readyToSubmit'),
            ),
          );
      await db
          .into(db.draftReports)
          .insert(
            DraftReportsCompanion.insert(
              id: 'r2',
              tenantId: 't1',
              createdAt: DateTime.now(),
              title: 'x',
              insertedUserId: 'u1',
              locationId: 'l1',
              submissionState: const Value('draft'), // must NOT count
            ),
          );
      await db
          .into(db.draftReports)
          .insert(
            DraftReportsCompanion.insert(
              id: 'r3',
              tenantId: 't1',
              createdAt: DateTime.now(),
              title: 'x',
              insertedUserId: 'u1',
              locationId: 'l1',
              submissionState: const Value('failed'),
            ),
          );
      await db
          .into(db.pendingTickets)
          .insert(
            PendingTicketsCompanion.insert(
              id: 'p1',
              createdAt: DateTime.now(),
              title: 'x',
              customerId: 'c1',
              locationId: 'l1',
              statusId: 1,
              typeId: 1,
              state: const Value('pendingSync'),
            ),
          );

      final container = ProviderContainer(
        overrides: [appDatabaseProvider.overrideWithValue(db)],
      );
      addTearDown(container.dispose);

      final result = await container.read(pendingSyncCountProvider.future);

      expect(result.pending, 2); // r1 (readyToSubmit) + p1 (pendingSync)
      expect(result.failed, 1); // r3
    },
  );
}
