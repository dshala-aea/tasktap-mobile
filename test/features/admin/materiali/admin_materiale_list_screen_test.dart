// dart format width=100
// test/features/admin/materiali/admin_materiale_list_screen_test.dart
//
// Covers only the barcode scan entry point added to this screen's search bar — the screen itself
// had no prior test coverage to extend.

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:tasktap_mobile/data/local/app_database.dart';
import 'package:tasktap_mobile/data/sync/sync_service.dart';
import 'package:tasktap_mobile/features/admin/materiali/admin_materiale_list_screen.dart';

AppDatabase _makeDb() => AppDatabase(NativeDatabase.memory());

Widget _buildScreen(AppDatabase db) {
  return ProviderScope(
    overrides: [appDatabaseProvider.overrideWithValue(db)],
    child: const MaterialApp(home: AdminMaterialeListScreen()),
  );
}

void main() {
  late AppDatabase db;

  setUp(() => db = _makeDb());
  tearDown(() async => db.close());

  testWidgets('shows a barcode scan button next to the search bar', (tester) async {
    await tester.pumpWidget(_buildScreen(db));
    await tester.pumpAndSettle();

    expect(find.byTooltip('Scansiona codice'), findsOneWidget);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
  });

  // An empty mirror is only a statement about the tenant once a sync has landed: before that it
  // says nothing, and the old single message told a fresh install the catalogue did not exist.
  testWidgets('never-synced empty mirror says the catalogue was not downloaded', (tester) async {
    await tester.pumpWidget(_buildScreen(db));
    await tester.pumpAndSettle();

    expect(find.text('Catalogo materiali non ancora scaricato'), findsOneWidget);
    expect(find.text('Catalogo materiali vuoto'), findsNothing);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
  });

  testWidgets('a synced, genuinely empty catalogue says so instead', (tester) async {
    await db.setLastSync(DateTime.utc(2026, 10, 1));
    await tester.pumpWidget(_buildScreen(db));
    await tester.pumpAndSettle();

    expect(find.text('Catalogo materiali vuoto'), findsOneWidget);
    expect(find.text('Catalogo materiali non ancora scaricato'), findsNothing);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
  });

  // A search that matched nothing is not a sync problem — it used to send the technician chasing
  // a nonexistent sync issue over a typo.
  testWidgets('a search with no match says no result, not "not downloaded"', (tester) async {
    await tester.pumpWidget(_buildScreen(db));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField), 'bullone inesistente');
    await tester.pumpAndSettle();

    expect(find.text('Nessun risultato'), findsOneWidget);
    expect(find.text('Catalogo materiali non ancora scaricato'), findsNothing);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
  });
}
