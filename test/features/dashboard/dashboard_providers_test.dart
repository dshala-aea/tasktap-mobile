import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tasktap_mobile/data/local/app_database.dart';
import 'package:tasktap_mobile/data/sync/sync_service.dart';
import 'package:tasktap_mobile/features/dashboard/dashboard_providers.dart';

void main() {
  late AppDatabase db;
  late ProviderContainer container;

  setUp(() {
    driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
    db = AppDatabase(NativeDatabase.memory());
    container = ProviderContainer(
      overrides: [appDatabaseProvider.overrideWithValue(db)],
    );
  });

  tearDown(() async {
    container.dispose();
    await db.close();
  });

  test('inProgressSchedulesProvider emits empty list when db empty', () async {
    final result = await container.read(inProgressSchedulesProvider.future);
    expect(result, isEmpty);
  });

  test('dashboardStatsProvider returns zeros when db empty', () {
    final stats = container.read(dashboardStatsProvider);
    expect(stats.todayCount, 0);
    expect(stats.inProgressCount, 0);
    expect(stats.completedCount, 0);
    expect(stats.upcomingCount, 0);
  });
}
