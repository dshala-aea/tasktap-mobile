// dart format width=100
import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tasktap_mobile/data/local/app_database.dart';
import 'package:tasktap_mobile/data/sync/sync_service.dart';
import 'package:tasktap_mobile/features/cantiere/cantiere_detail_screen.dart';

void main() {
  testWidgets('shows cantiere info and an empty tickets section', (tester) async {
    final db = AppDatabase(NativeDatabase.memory());
    await db
        .into(db.cantieri)
        .insert(
          CantieriCompanion.insert(
            id: 'c1',
            tenantId: 'tenant1',
            createdAt: DateTime.utc(2026, 8, 31),
            name: 'Cantiere Alpha',
            address: const Value('Via Roma 1'),
          ),
        );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [appDatabaseProvider.overrideWithValue(db)],
        child: const MaterialApp(home: CantiereDetailScreen(cantiereId: 'c1')),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Cantiere Alpha'), findsOneWidget);
    expect(find.text('Via Roma 1'), findsOneWidget);
    expect(find.text('Timbra cantiere'), findsOneWidget);
    expect(find.text('Nessun ticket collegato'), findsOneWidget);

    await db.close();
  });

  testWidgets('lists linked tickets when present', (tester) async {
    final db = AppDatabase(NativeDatabase.memory());
    await db
        .into(db.cantieri)
        .insert(
          CantieriCompanion.insert(
            id: 'c1',
            tenantId: 'tenant1',
            createdAt: DateTime.utc(2026, 8, 31),
            name: 'Cantiere Alpha',
          ),
        );
    await db
        .into(db.tickets)
        .insert(
          TicketsCompanion.insert(
            id: 't1',
            tenantId: 'tenant1',
            createdAt: DateTime.utc(2026, 8, 31),
            title: 'Ticket collegato',
            customerId: 'cust1',
            locationId: 'l1',
            statusId: 1,
            typeId: 1,
            cantiereId: const Value('c1'),
          ),
        );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [appDatabaseProvider.overrideWithValue(db)],
        child: const MaterialApp(home: CantiereDetailScreen(cantiereId: 'c1')),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Ticket collegato'), findsOneWidget);

    await db.close();
  });
}
