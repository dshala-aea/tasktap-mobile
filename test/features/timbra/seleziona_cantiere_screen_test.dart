// test/features/timbra/seleziona_cantiere_screen_test.dart
//
// Widget tests for SelezionaCantiereScreen — the full-screen cantiere picker extracted from
// CantiereTimbraScreen's old `showPicker: true` inline picker (see that screen's own header
// comment on the redesign). Most of these assertions were previously in
// cantiere_timbra_screen_test.dart's "no active session" group, pumping CantiereTimbraScreen with
// no cantiereId at all — moved here, adapted to the new screen, plus new coverage for the search
// filter and the tap-to-navigate behaviour that didn't exist on the old inline picker.

import 'package:drift/drift.dart' show Value, driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:tasktap_mobile/core/router/app_router.dart';
import 'package:tasktap_mobile/data/local/app_database.dart';
import 'package:tasktap_mobile/data/sync/sync_service.dart';
import 'package:tasktap_mobile/features/timbra/seleziona_cantiere_screen.dart';

AppDatabase _makeDb() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  return AppDatabase(NativeDatabase.memory());
}

Future<void> _teardown(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pumpAndSettle();
}

/// Builds SelezionaCantiereScreen with a real [GoRouter] behind it, with a marker screen at
/// `AppRoutes.cantiereTimbra` so a test can assert exactly which cantiereId/ticketId/customerId
/// query params a tap navigated with.
Widget _buildScreen({
  required AppDatabase db,
  String? ticketId,
  String? customerId,
}) {
  final router = GoRouter(
    initialLocation: AppRoutes.selezionaCantierePath(ticketId: ticketId, customerId: customerId),
    routes: [
      GoRoute(
        path: AppRoutes.selezionaCantiere,
        builder: (context, state) => SelezionaCantiereScreen(
          ticketId: state.uri.queryParameters['ticketId'],
          customerId: state.uri.queryParameters['customerId'],
        ),
      ),
      GoRoute(
        path: AppRoutes.cantiereTimbra,
        builder: (context, state) => Scaffold(
          body: Center(
            child: Text(
              'CANTIERE-TIMBRA-MARKER '
              'cantiereId=${state.uri.queryParameters['cantiereId']} '
              'ticketId=${state.uri.queryParameters['ticketId']} '
              'customerId=${state.uri.queryParameters['customerId']}',
            ),
          ),
        ),
      ),
    ],
  );

  return ProviderScope(
    overrides: [appDatabaseProvider.overrideWithValue(db)],
    child: MaterialApp.router(routerConfig: router),
  );
}

void main() {
  setUpAll(() {
    driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  });

  late AppDatabase db;
  setUp(() => db = _makeDb());
  tearDown(() async => db.close());

  Future<void> seed(AppDatabase db, {String id = 'cant-1', String? city, String? customerId}) =>
      db
          .into(db.cantieri)
          .insert(
            CantieriCompanion.insert(
              id: id,
              tenantId: 'tenant-1',
              createdAt: DateTime.utc(2026, 1, 1),
              name: id == 'cant-1' ? 'Cantiere Via Roma' : 'Cantiere $id',
              city: city == null ? const Value.absent() : Value(city),
              customerId: customerId == null ? const Value.absent() : Value(customerId),
            ),
          );

  testWidgets('renders Seleziona cantiere header', (tester) async {
    await tester.pumpWidget(_buildScreen(db: db));
    await tester.pumpAndSettle();

    expect(find.text('Seleziona cantiere'), findsOneWidget);
    await _teardown(tester);
  });

  testWidgets('shows cantiere rows from Drift', (tester) async {
    await seed(db);
    await tester.pumpWidget(_buildScreen(db: db));
    await tester.pumpAndSettle();

    expect(find.text('Cantiere Via Roma'), findsOneWidget);
    await _teardown(tester);
  });

  testWidgets('shows an honest empty state when no cantieri in cache', (tester) async {
    await tester.pumpWidget(_buildScreen(db: db));
    await tester.pumpAndSettle();

    expect(find.text('Nessun cantiere disponibile'), findsOneWidget);
    await _teardown(tester);
  });

  testWidgets('filters rows by name as the technician types', (tester) async {
    await seed(db, id: 'cant-1');
    await seed(db, id: 'cant-2', city: 'Bergamo');
    await tester.pumpWidget(_buildScreen(db: db));
    await tester.pumpAndSettle();

    expect(find.text('Cantiere Via Roma'), findsOneWidget);
    expect(find.text('Cantiere cant-2'), findsOneWidget);

    await tester.enterText(find.byType(TextField), 'Via Roma');
    await tester.pumpAndSettle();

    expect(find.text('Cantiere Via Roma'), findsOneWidget);
    expect(find.text('Cantiere cant-2'), findsNothing);

    await _teardown(tester);
  });

  testWidgets('filters rows by city as the technician types', (tester) async {
    await seed(db, id: 'cant-1', city: 'Milano');
    await seed(db, id: 'cant-2', city: 'Bergamo');
    await tester.pumpWidget(_buildScreen(db: db));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField), 'bergamo');
    await tester.pumpAndSettle();

    expect(find.text('Cantiere cant-2'), findsOneWidget);
    expect(find.text('Cantiere Via Roma'), findsNothing);

    await _teardown(tester);
  });

  testWidgets('shows a no-results state when the search matches nothing', (tester) async {
    await seed(db);
    await tester.pumpWidget(_buildScreen(db: db));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField), 'nessuna corrispondenza');
    await tester.pumpAndSettle();

    expect(find.text('Nessun risultato'), findsOneWidget);
    expect(find.text('Cantiere Via Roma'), findsNothing);

    await _teardown(tester);
  });

  testWidgets(
    'tapping a row navigates to CantiereTimbraScreen with the tapped cantiereId',
    (tester) async {
      await seed(db);
      await tester.pumpWidget(_buildScreen(db: db, ticketId: 'tick-1', customerId: 'cust-1'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Cantiere Via Roma'));
      await tester.pumpAndSettle();

      expect(
        find.text(
          'CANTIERE-TIMBRA-MARKER cantiereId=cant-1 ticketId=tick-1 customerId=cust-1',
        ),
        findsOneWidget,
      );
      // Seleziona-cantiere itself is gone — pushReplacement, not push (see this screen's own
      // header comment on why: the back button must not return to a stale search screen).
      expect(find.text('Seleziona cantiere'), findsNothing);

      await _teardown(tester);
    },
  );
}
