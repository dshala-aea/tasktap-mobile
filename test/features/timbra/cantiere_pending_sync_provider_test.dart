// The cantiere sibling of the Timbra pending flag, for the same reason:
// `cantiereHasPendingSyncProvider` must not count the cantiere reconciler's own display-only
// corrections. They are pending by construction (they are never uploaded) and counting them left
// the "Non sincronizzato" state stuck and the punch guard frozen.

import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tasktap_mobile/data/local/app_database.dart';
import 'package:tasktap_mobile/data/sync/sync_service.dart' show appDatabaseProvider;
import 'package:tasktap_mobile/data/timbratura/cantiere_timbra_sync_service.dart'
    show cantiereSessionRepositoryProvider;
import 'package:tasktap_mobile/features/timbra/cantiere_timbra_screen.dart'
    show cantiereHasPendingSyncProvider, todayCantiereEventsProvider;

void main() {
  late AppDatabase db;
  late ProviderContainer container;

  setUp(() {
    driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
    db = AppDatabase(NativeDatabase.memory());
    container = ProviderContainer(
      retry: (_, _) => null,
      overrides: [appDatabaseProvider.overrideWithValue(db)],
    );
  });

  tearDown(() async {
    container.dispose();
    await db.close();
  });

  Future<void> readToday() async {
    container.listen(todayCantiereEventsProvider, (_, _) {});
    await container.read(todayCantiereEventsProvider.future);
  }

  test('ignores the cantiere reconciler mirrors', () async {
    final repo = container.read(cantiereSessionRepositoryProvider);
    await repo.addEvent(
      id: 'mirror',
      eventTime: DateTime.now().toUtc(),
      eventType: 'ingresso',
      cantiereId: 'c1',
    );
    await repo.markReconciledOrphan('mirror');

    await readToday();

    expect(container.read(cantiereHasPendingSyncProvider), isFalse);
  });

  test('still reports a real unsent cantiere punch', () async {
    final repo = container.read(cantiereSessionRepositoryProvider);
    await repo.addEvent(
      id: 'real',
      eventTime: DateTime.now().toUtc(),
      eventType: 'ingresso',
      cantiereId: 'c1',
    );

    await readToday();

    expect(container.read(cantiereHasPendingSyncProvider), isTrue);
  });
}
