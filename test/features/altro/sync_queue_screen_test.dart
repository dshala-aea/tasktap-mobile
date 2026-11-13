// dart format width=100
import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tasktap_mobile/core/theme/app_theme.dart';
import 'package:tasktap_mobile/data/local/app_database.dart';
import 'package:tasktap_mobile/data/sync/sync_service.dart' show appDatabaseProvider;
import 'package:tasktap_mobile/data/timbratura/work_session_repository.dart';
import 'package:tasktap_mobile/features/altro/sync_queue_screen.dart';

void main() {
  late AppDatabase db;
  late WorkSessionRepository repo;

  setUp(() {
    driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
    db = AppDatabase(NativeDatabase.memory());
    repo = WorkSessionRepository(db);
  });
  tearDown(() => db.close());

  Future<void> pump(WidgetTester tester) async {
    await tester.pumpWidget(
      ProviderScope(retry: (_, _) => null, 
        overrides: [appDatabaseProvider.overrideWithValue(db)],
        child: MaterialApp(theme: buildAppTheme(), home: const SyncQueueScreen()),
      ),
    );
    await tester.pumpAndSettle();
  }

  /// Unmounts the screen so Drift's zero-duration stream timers are flushed (same as the timbra
  /// screen tests).
  Future<void> unmount(WidgetTester tester) async {
    await tester.pumpWidget(const MaterialApp(home: SizedBox()));
    for (var i = 0; i < 5; i++) {
      await tester.pump(Duration.zero);
    }
  }

  final t0 = DateTime.utc(2026, 11, 6, 8, 11);

  Future<void> seed() async {
    await repo.addEvent(id: 'in', eventTime: t0, eventType: 'ingresso');
    await repo.addEvent(
      id: 'pausa',
      eventTime: t0.add(const Duration(minutes: 7)),
      eventType: 'pausa',
    );
    await repo.addEvent(
      id: 'old',
      eventTime: t0.subtract(const Duration(days: 1)),
      eventType: 'ingresso',
    );
    await repo.markSyncFailed('old');
  }

  testWidgets('empty state', (tester) async {
    await pump(tester);
    expect(find.text('Nessuna timbratura in coda'), findsOneWidget);
    await unmount(tester);
  });

  testWidgets('lists pending and refused items with their state', (tester) async {
    await seed();
    await pump(tester);
    expect(find.text('in attesa'), findsNWidgets(2));
    expect(find.text('non inviato — rifiutato'), findsOneWidget);
    expect(find.text('Riprova ora'), findsOneWidget);
    await unmount(tester);
  });

  testWidgets('delete asks for confirmation and removes the newest pending item', (tester) async {
    await seed();
    await pump(tester);
    await tester.tap(find.byTooltip(RegExp(r'^Elimina Pausa')));
    await tester.pumpAndSettle();
    expect(find.text('Eliminare la timbratura?'), findsOneWidget);
    await tester.tap(find.widgetWithText(TextButton, 'Elimina'));
    await tester.pumpAndSettle();

    expect(find.byTooltip(RegExp(r'^Elimina Pausa')), findsNothing);
    final rows = await db.select(db.workSessions).get();
    expect(rows.map((r) => r.id), isNot(contains('pausa')));
    await unmount(tester);
  });

  testWidgets('cancelling the confirmation keeps the item', (tester) async {
    await seed();
    await pump(tester);
    await tester.tap(find.byTooltip(RegExp(r'^Elimina Pausa')));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(TextButton, 'Annulla'));
    await tester.pumpAndSettle();

    expect(find.byTooltip(RegExp(r'^Elimina Pausa')), findsOneWidget);
    expect((await db.select(db.workSessions).get()).map((r) => r.id), contains('pausa'));
    await unmount(tester);
  });

  testWidgets('a pending opener with later pending events is refused, not deleted', (tester) async {
    await seed();
    await pump(tester);
    await tester.tap(find.byTooltip(RegExp(r'^Elimina Inizio turno')).last);
    await tester.pumpAndSettle();

    expect(find.text('Eliminare la timbratura?'), findsNothing);
    expect(find.textContaining('Elimina prima le timbrature successive'), findsOneWidget);
    expect((await db.select(db.workSessions).get()).map((r) => r.id), contains('in'));
    await unmount(tester);
  });
}
