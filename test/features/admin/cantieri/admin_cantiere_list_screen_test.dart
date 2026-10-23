// dart format width=100
// test/features/admin/cantieri/admin_cantiere_list_screen_test.dart
//
// Pins the three-way empty state of the admin cantieri list. The search-no-match branch already
// existed; this covers the other two, which used to share "Cantieri non disponibili" — telling a
// tenant with no cantieri that theirs had not been synced.

import 'package:drift/drift.dart' hide isNotNull;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:tasktap_mobile/data/local/app_database.dart';
import 'package:tasktap_mobile/data/sync/sync_service.dart';
import 'package:tasktap_mobile/features/admin/cantieri/admin_cantiere_list_screen.dart';

AppDatabase _makeDb() => AppDatabase(NativeDatabase.memory());

Widget _buildScreen(AppDatabase db) => ProviderScope(
  overrides: [appDatabaseProvider.overrideWithValue(db)],
  child: const MaterialApp(home: AdminCantiereListScreen()),
);

void main() {
  setUpAll(() {
    driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  });

  late AppDatabase db;
  setUp(() => db = _makeDb());
  tearDown(() async => db.close());

  testWidgets('never-synced empty mirror says the cantieri were not downloaded', (tester) async {
    await tester.pumpWidget(_buildScreen(db));
    await tester.pumpAndSettle();

    expect(find.text('Cantieri non ancora scaricati'), findsOneWidget);
    expect(find.text('Nessun cantiere'), findsNothing);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
  });

  testWidgets('a synced, genuinely empty list offers the create action', (tester) async {
    await db.setLastSync(DateTime.utc(2026, 10, 1));
    await tester.pumpWidget(_buildScreen(db));
    await tester.pumpAndSettle();

    expect(find.text('Nessun cantiere'), findsOneWidget);
    expect(find.text('Cantieri non ancora scaricati'), findsNothing);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
  });

  testWidgets('a search with no match says no result, not "not downloaded"', (tester) async {
    await tester.pumpWidget(_buildScreen(db));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField), 'cantiere inesistente');
    await tester.pumpAndSettle();

    expect(find.text('Nessun risultato'), findsOneWidget);
    expect(find.text('Cantieri non ancora scaricati'), findsNothing);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
  });
}
