import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tasktap_mobile/data/local/app_database.dart';
import 'package:tasktap_mobile/data/sync/sync_service.dart';
import 'package:tasktap_mobile/features/cantiere/cantieri_list_screen.dart';

void main() {
  // The empty state's own copy tells the technician to "trascina in basso per aggiornare" —
  // this asserts the RefreshIndicator can actually fire there, not just that a Scrollable
  // exists somewhere off in the populated-list branch. Regression test for the earlier bug where
  // RefreshIndicator wrapped `cantieriAsync.when(...)` and only its `data` branch contained a
  // Scrollable, so pull-to-refresh silently did nothing in the empty/loading/error states.
  testWidgets('pull-to-refresh is reachable in the empty state', (tester) async {
    final db = AppDatabase(NativeDatabase.memory());

    await tester.pumpWidget(
      ProviderScope(
        overrides: [appDatabaseProvider.overrideWithValue(db)],
        child: const MaterialApp(home: CantieriListScreen()),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Nessun cantiere disponibile'), findsOneWidget);
    expect(find.byType(RefreshIndicator), findsOneWidget);

    // The whole page (header + empty state) is one Scrollable inside the RefreshIndicator, so a
    // drag anywhere on it should be able to trigger the indicator rather than being swallowed by
    // a non-scrolling child.
    await tester.fling(find.byType(CustomScrollView), const Offset(0, 300), 1000);
    await tester.pump();
    expect(find.byType(RefreshProgressIndicator), findsOneWidget);
    await tester.pumpAndSettle();

    await db.close();
  });


  testWidgets('shows an empty state when no cantieri are synced', (tester) async {
    final db = AppDatabase(NativeDatabase.memory());

    await tester.pumpWidget(
      ProviderScope(
        overrides: [appDatabaseProvider.overrideWithValue(db)],
        child: const MaterialApp(home: CantieriListScreen()),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Nessun cantiere disponibile'), findsOneWidget);

    await db.close();
  });

  testWidgets('lists synced cantieri alphabetically', (tester) async {
    final db = AppDatabase(NativeDatabase.memory());
    await db
        .into(db.cantieri)
        .insert(
          CantieriCompanion.insert(
            id: 'c2',
            tenantId: 'tenant1',
            createdAt: DateTime.utc(2026, 8, 31),
            name: 'Zeta Cantiere',
          ),
        );
    await db
        .into(db.cantieri)
        .insert(
          CantieriCompanion.insert(
            id: 'c1',
            tenantId: 'tenant1',
            createdAt: DateTime.utc(2026, 8, 31),
            name: 'Alfa Cantiere',
          ),
        );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [appDatabaseProvider.overrideWithValue(db)],
        child: const MaterialApp(home: CantieriListScreen()),
      ),
    );
    await tester.pumpAndSettle();

    final alfaFinder = find.text('Alfa Cantiere');
    final zetaFinder = find.text('Zeta Cantiere');
    expect(alfaFinder, findsOneWidget);
    expect(zetaFinder, findsOneWidget);
    expect(
      tester.getTopLeft(alfaFinder).dy,
      lessThan(tester.getTopLeft(zetaFinder).dy),
    );

    await db.close();
  });
}
