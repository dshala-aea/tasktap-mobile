import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tasktap_mobile/data/local/app_database.dart';
import 'package:tasktap_mobile/data/sync/sync_service.dart';
import 'package:tasktap_mobile/features/cantiere/cantieri_list_screen.dart';

void main() {
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
