// dart format width=100
// test/features/admin/locations/admin_location_list_screen_test.dart
//
// Pins the three-way empty state: a filter that matched nothing, a phone that never completed a
// sync, and a tenant with no sedi all used to share one message ("Nessuna sede"), which sent a
// technician to create a duplicate of a sede that was simply not downloaded yet.

import 'package:drift/drift.dart' hide isNotNull;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:tasktap_mobile/data/local/app_database.dart';
import 'package:tasktap_mobile/data/sync/sync_service.dart';
import 'package:tasktap_mobile/features/admin/locations/admin_location_list_screen.dart';

AppDatabase _makeDb() => AppDatabase(NativeDatabase.memory());

Widget _buildScreen(AppDatabase db) => ProviderScope(
  overrides: [appDatabaseProvider.overrideWithValue(db)],
  child: const MaterialApp(home: AdminLocationListScreen()),
);

void main() {
  setUpAll(() {
    driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  });

  late AppDatabase db;
  setUp(() => db = _makeDb());
  tearDown(() async => db.close());

  testWidgets('never-synced empty mirror says the sedi were not downloaded', (tester) async {
    await tester.pumpWidget(_buildScreen(db));
    await tester.pumpAndSettle();

    expect(find.text('Sedi non ancora scaricate'), findsOneWidget);
    expect(find.text('Nessuna sede'), findsNothing);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
  });

  testWidgets('a synced, genuinely empty list offers the create action', (tester) async {
    await db.setLastSync(DateTime.utc(2026, 10, 1));
    await tester.pumpWidget(_buildScreen(db));
    await tester.pumpAndSettle();

    expect(find.text('Nessuna sede'), findsOneWidget);
    expect(find.text('Sedi non ancora scaricate'), findsNothing);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
  });

  testWidgets('a search with no match says no result, not "not downloaded"', (tester) async {
    await tester.pumpWidget(_buildScreen(db));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField), 'sede inesistente');
    await tester.pumpAndSettle();

    expect(find.text('Nessun risultato'), findsOneWidget);
    expect(find.text('Sedi non ancora scaricate'), findsNothing);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
  });
}
