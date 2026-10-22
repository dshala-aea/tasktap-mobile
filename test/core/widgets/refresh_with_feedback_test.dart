// dart format width=100
//
// `refreshWithFeedback` — every pull-to-refresh in the app goes through it, because
// `SyncNotifier.performSync()` never throws: a failed sync is parked in `SyncState.status` and a
// caller that does not read it back leaves the technician looking at stale data that stopped
// spinning as though it were fresh. The dashboard had this check inline; the other refresh sites
// did not.
import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tasktap_mobile/core/widgets/refresh_with_feedback.dart';
import 'package:tasktap_mobile/data/local/app_database.dart';
import 'package:tasktap_mobile/data/sync/sync_service.dart';

/// Stands in for the notifier's one observable effect: the state it leaves behind.
class _StubSyncNotifier extends SyncNotifier {
  _StubSyncNotifier(SyncService service, AppDatabase db, {required this.outcome})
    : super(service, db);

  final SyncStatus outcome;

  @override
  Future<void> performSync() async {
    state = SyncState(
      status: outcome,
      errorMessage: outcome == SyncStatus.error ? 'boom' : null,
    );
  }
}

void main() {
  late AppDatabase db;

  setUp(() {
    driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
    db = AppDatabase(NativeDatabase.memory());
  });

  tearDown(() => db.close());

  Future<void> pumpAndRefresh(WidgetTester tester, SyncStatus outcome) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          appDatabaseProvider.overrideWithValue(db),
          syncProvider.overrideWith(
            (ref) => _StubSyncNotifier(ref.watch(syncServiceProvider), db, outcome: outcome),
          ),
        ],
        child: MaterialApp(
          home: Scaffold(
            body: Consumer(
              builder: (context, ref, _) => ElevatedButton(
                onPressed: () => refreshWithFeedback(context, ref),
                child: const Text('refresh'),
              ),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('refresh'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
  }

  testWidgets('a failed sync says so instead of ending in silence', (tester) async {
    await pumpAndRefresh(tester, SyncStatus.error);

    expect(find.text('Aggiornamento non riuscito. Riprova.'), findsOneWidget);
  });

  testWidgets('a successful sync stays quiet', (tester) async {
    await pumpAndRefresh(tester, SyncStatus.done);

    expect(find.text('Aggiornamento non riuscito. Riprova.'), findsNothing);
  });
}
