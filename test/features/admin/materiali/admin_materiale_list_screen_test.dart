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
}
