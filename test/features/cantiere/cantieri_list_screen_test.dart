import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tasktap_mobile/core/time/business_time.dart';
import 'package:tasktap_mobile/data/local/app_database.dart';
import 'package:tasktap_mobile/data/sync/sync_service.dart';
import 'package:tasktap_mobile/features/cantiere/cantieri_list_screen.dart';

Future<void> _pumpScreen(
  WidgetTester tester,
  AppDatabase db, {
  List<Override> extraOverrides = const [],
}) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [appDatabaseProvider.overrideWithValue(db), ...extraOverrides],
      child: const MaterialApp(home: CantieriListScreen()),
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> _insertCantiere(
  AppDatabase db, {
  required String id,
  required String name,
  int status = 0,
  String? customerId,
  String? city,
  String? address,
  DateTime? startDate,
  DateTime? endDate,
}) {
  return db
      .into(db.cantieri)
      .insert(
        CantieriCompanion.insert(
          id: id,
          tenantId: 'tenant1',
          createdAt: DateTime.utc(2026, 8, 31),
          name: name,
          status: Value(status),
          customerId: Value(customerId),
          city: Value(city),
          address: Value(address),
          startDate: Value(startDate),
          endDate: Value(endDate),
        ),
      );
}

Future<void> _insertCustomer(AppDatabase db, String id, String name) {
  return db
      .into(db.customers)
      .insert(
        CustomersCompanion.insert(
          id: id,
          tenantId: 'tenant1',
          createdAt: DateTime.utc(2026, 1, 1),
          companyName: name,
        ),
      );
}

/// Inserts a closed ingresso→uscita interval at 08:00–09:00 of the business day today.
Future<void> _insertPunchToday(AppDatabase db, String cantiereId) async {
  final bt = BusinessTime.fallback();
  final start = bt
      .utcRangeForBusinessDate(bt.businessToday())
      .$1
      .add(const Duration(hours: 8));
  await db
      .into(db.cantierePunches)
      .insert(
        CantierePunchesCompanion.insert(
          id: 'e-$cantiereId-1',
          eventTime: start,
          eventType: 'ingresso',
          cantiereId: Value(cantiereId),
        ),
      );
  await db
      .into(db.cantierePunches)
      .insert(
        CantierePunchesCompanion.insert(
          id: 'e-$cantiereId-2',
          eventTime: start.add(const Duration(hours: 1)),
          eventType: 'uscita',
        ),
      );
}

void main() {
  // The empty state's own copy tells the technician to "trascina in basso per aggiornare" —
  // this asserts the RefreshIndicator can actually fire there, not just that a Scrollable
  // exists somewhere off in the populated-list branch. Regression test for the earlier bug where
  // RefreshIndicator wrapped `cantieriAsync.when(...)` and only its `data` branch contained a
  // Scrollable, so pull-to-refresh silently did nothing in the empty/loading/error states.
  testWidgets('pull-to-refresh is reachable in the empty state', (
    tester,
  ) async {
    final db = AppDatabase(NativeDatabase.memory());
    // Seeded so the screen is past its first sync: that is the branch whose copy tells the
    // technician to pull down, and the one this test is about.
    await db.setLastSync(DateTime.utc(2026, 10, 1));

    await _pumpScreen(tester, db);

    expect(find.text('Nessun cantiere in corso'), findsOneWidget);
    expect(find.byType(RefreshIndicator), findsOneWidget);

    // The whole page is one Scrollable inside the RefreshIndicator, so a drag anywhere on it
    // should be able to trigger the indicator rather than being swallowed by a non-scrolling
    // child.
    await tester.fling(
      find.byType(CustomScrollView),
      const Offset(0, 300),
      1000,
    );
    await tester.pump();
    expect(find.byType(RefreshProgressIndicator), findsOneWidget);
    await tester.pumpAndSettle();

    await db.close();
  });

  /// "no cantieri synced on this device" is a claim about the phone, so it may only be made
  /// before the first completed sync. After one, the empty mirror is the technician's actual
  /// scope, and the copy must not send them to refresh for data that has already arrived.
  testWidgets(
    'a device that never synced says so instead of "no cantieri in progress"',
    (tester) async {
      final db = AppDatabase(NativeDatabase.memory());

      await _pumpScreen(tester, db);

      expect(find.text('Cantieri non ancora scaricati'), findsOneWidget);
      expect(find.text('Nessun cantiere in corso'), findsNothing);

      await db.close();
    },
  );

  testWidgets('no Nuovo action: technicians have no create route', (
    tester,
  ) async {
    final db = AppDatabase(NativeDatabase.memory());
    await _insertCantiere(db, id: 'c1', name: 'Alfa Cantiere');

    await _pumpScreen(tester, db);

    // The prototype shows `Nuovo`, but the only cantiere-create route is the admin
    // `/altro/cantieri/nuovo` (dispatcher-gated). A technician list must not show a
    // dead control, so no header action is rendered.
    expect(find.text('NUOVO'), findsNothing);

    await db.close();
  });

  testWidgets('lists synced cantieri alphabetically', (tester) async {
    final db = AppDatabase(NativeDatabase.memory());
    await _insertCantiere(db, id: 'c2', name: 'Zeta Cantiere');
    await _insertCantiere(db, id: 'c1', name: 'Alfa Cantiere');

    await _pumpScreen(tester, db);

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

  testWidgets('groups active cantieri into today, other active and planned', (
    tester,
  ) async {
    final db = AppDatabase(NativeDatabase.memory());
    await _insertCantiere(db, id: 'c1', name: 'Alfa Cantiere');
    await _insertCantiere(db, id: 'c2', name: 'Bravo Cantiere');
    await _insertPunchToday(db, 'c1');
    await _insertCantiere(
      db,
      id: 'c3',
      name: 'Charlie Pianificato',
      startDate: DateTime.now().add(const Duration(days: 2)),
    );

    await _pumpScreen(tester, db);

    expect(find.text('Da seguire oggi'), findsOneWidget);
    expect(find.text('Altri cantieri attivi'), findsOneWidget);
    expect(find.text('Pianificati'), findsOneWidget);
    // The prototype subtitle and search hint are part of the redesign.
    expect(
      find.text('Cosa devo seguire oggi, e quali cantieri sono ancora attivi.'),
      findsOneWidget,
    );
    expect(
      find.text('Cerca cantiere, cliente, indirizzo o codice…'),
      findsOneWidget,
    );
    // Summary counts derive from the filtered set.
    expect(find.text('3 CANTIERI ATTIVI'), findsOneWidget);
    expect(find.text('1 OGGI'), findsOneWidget);

    await db.close();
  });

  testWidgets(
    'quick chips switch between attivi, pianificati, chiusi and tutti',
    (tester) async {
      final db = AppDatabase(NativeDatabase.memory());
      await _insertCantiere(db, id: 'c1', name: 'Alfa Attivo');
      await _insertCantiere(
        db,
        id: 'c2',
        name: 'Bravo Pianificato',
        startDate: DateTime.now().add(const Duration(days: 2)),
      );
      await _insertCantiere(db, id: 'c3', name: 'Charlie Chiuso', status: 1);

      await _pumpScreen(tester, db);

      expect(find.text('Alfa Attivo'), findsOneWidget);
      expect(find.text('Bravo Pianificato'), findsOneWidget);
      expect(find.text('Charlie Chiuso'), findsNothing);

      await tester.tap(find.text('CHIUSI'));
      await tester.pumpAndSettle();
      expect(find.text('Charlie Chiuso'), findsOneWidget);
      expect(find.text('Alfa Attivo'), findsNothing);
      expect(find.text('Chiusi'), findsOneWidget);

      await tester.tap(find.text('PIANIFICATI'));
      await tester.pumpAndSettle();
      expect(find.text('Bravo Pianificato'), findsOneWidget);
      expect(find.text('Charlie Chiuso'), findsNothing);

      await tester.tap(find.text('TUTTI'));
      await tester.pumpAndSettle();
      expect(find.text('Alfa Attivo'), findsOneWidget);
      expect(find.text('Bravo Pianificato'), findsOneWidget);
      expect(find.text('Charlie Chiuso'), findsOneWidget);

      await db.close();
    },
  );

  testWidgets('search matches cantiere name, customer and city', (
    tester,
  ) async {
    final db = AppDatabase(NativeDatabase.memory());
    await _insertCustomer(db, 'cust1', 'Rossi Srl');
    await _insertCustomer(db, 'cust2', 'Bianchi Srl');
    await _insertCantiere(
      db,
      id: 'c1',
      name: 'Ristrutturazione Via Roma',
      customerId: 'cust1',
      city: 'Milano',
    );
    await _insertCantiere(
      db,
      id: 'c2',
      name: 'Manutenzione caldaie',
      customerId: 'cust2',
      city: 'Sesto',
    );

    await _pumpScreen(tester, db);

    await tester.enterText(find.byType(TextField), 'Rossi');
    await tester.pumpAndSettle();
    expect(find.text('Ristrutturazione Via Roma'), findsOneWidget);
    expect(find.text('Manutenzione caldaie'), findsNothing);

    await tester.enterText(find.byType(TextField), 'Sesto');
    await tester.pumpAndSettle();
    expect(find.text('Manutenzione caldaie'), findsOneWidget);
    expect(find.text('Ristrutturazione Via Roma'), findsNothing);

    await tester.enterText(find.byType(TextField), 'nessuno');
    await tester.pumpAndSettle();
    expect(find.text('Nessun risultato'), findsOneWidget);

    await db.close();
  });

  testWidgets(
    'filter sheet has the local facets and the today toggle narrows the list',
    (tester) async {
      final db = AppDatabase(NativeDatabase.memory());
      await _insertCustomer(db, 'cust1', 'Rossi Srl');
      await _insertCantiere(
        db,
        id: 'c1',
        name: 'Alfa Oggi',
        customerId: 'cust1',
        city: 'Milano',
      );
      await _insertPunchToday(db, 'c1');
      await _insertCantiere(
        db,
        id: 'c2',
        name: 'Bravo Altro',
        customerId: 'cust1',
        city: 'Milano',
      );

      await _pumpScreen(tester, db);

      await tester.tap(find.text('FILTRI'));
      await tester.pumpAndSettle();

      expect(find.text('Filtri'), findsOneWidget);
      expect(find.text('STATO'), findsOneWidget);
      expect(find.text('CLIENTE'), findsOneWidget);
      expect(find.text('SEDE'), findsOneWidget);
      expect(find.text('PERIODO'), findsOneWidget);
      expect(find.text('Solo da seguire oggi'), findsOneWidget);
      // No squadra column on the local cantiere mirror, so the facet is not offered.
      expect(find.text('SQUADRA'), findsNothing);

      await tester.tap(find.byKey(const Key('cantieriFilterOnlyToday')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('cantieriFilterApply')));
      await tester.pumpAndSettle();

      expect(find.text('Alfa Oggi'), findsOneWidget);
      expect(find.text('Bravo Altro'), findsNothing);

      // Azzera clears the toggle and restores the full set.
      await tester.tap(find.text('FILTRI'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('cantieriFilterReset')));
      await tester.pumpAndSettle();
      expect(find.text('Alfa Oggi'), findsOneWidget);
      expect(find.text('Bravo Altro'), findsOneWidget);

      await db.close();
    },
  );

  testWidgets('row meta shows customer, place and crew size', (tester) async {
    final db = AppDatabase(NativeDatabase.memory());
    await _insertCustomer(db, 'cust1', 'Rossi Srl');
    await _insertCantiere(
      db,
      id: 'c1',
      name: 'Ristrutturazione Via Roma',
      customerId: 'cust1',
      city: 'Milano',
    );
    await db
        .into(db.cantiereCrewAssignments)
        .insert(
          CantiereCrewAssignmentsCompanion.insert(
            id: 'a1',
            cantiereId: 'c1',
            userId: 'u1',
          ),
        );
    await db
        .into(db.cantiereCrewAssignments)
        .insert(
          CantiereCrewAssignmentsCompanion.insert(
            id: 'a2',
            cantiereId: 'c1',
            userId: 'u2',
          ),
        );

    await _pumpScreen(tester, db);

    expect(find.text('Rossi Srl · Milano · 2 operatori'), findsOneWidget);

    await db.close();
  });

  // ── "Timbrato oggi" per-row indicator ───────────────────────────────────
  //
  // Reuses cantiereTodayHoursProvider/cantiereActiveSessionProvider — the same "did I log any
  // cantiere worklog today for this cantiere" signal cantiere_timbra_screen.dart's own OGGI
  // header already reads — rather than a new query.

  testWidgets(
    'shows a "Timbrato oggi" line for a cantiere with a closed interval today',
    (tester) async {
      final db = AppDatabase(NativeDatabase.memory());
      await _insertCantiere(db, id: 'c1', name: 'Alfa Cantiere');
      await _insertPunchToday(db, 'c1');

      await _pumpScreen(tester, db);

      expect(find.textContaining('Timbrato oggi'), findsOneWidget);
      expect(find.textContaining('08:00–09:00'), findsOneWidget);

      await db.close();
    },
  );

  testWidgets(
    'shows no "Timbrato oggi" line for a cantiere with no punches today',
    (tester) async {
      final db = AppDatabase(NativeDatabase.memory());
      await _insertCantiere(db, id: 'c1', name: 'Alfa Cantiere');

      await _pumpScreen(tester, db);

      expect(find.text('Alfa Cantiere'), findsOneWidget);
      expect(find.textContaining('Timbrato oggi'), findsNothing);
      expect(find.text('Nessuna attività oggi'), findsOneWidget);

      await db.close();
    },
  );

  testWidgets(
    'planned rows show a civil start date, never a device-zone shift',
    (tester) async {
      final db = AppDatabase(NativeDatabase.memory());
      await _insertCantiere(
        db,
        id: 'c1',
        name: 'Alfa Pianificato',
        startDate: DateTime.utc(2099, 11, 18),
      );

      await _pumpScreen(tester, db);

      // The wire sends a UTC midnight; `toLocal()` west of UTC would show 17/11.
      expect(find.text('Inizio · 18/11'), findsOneWidget);

      await db.close();
    },
  );

  testWidgets('the summary does not claim 0 attivi under the Chiusi chip', (
    tester,
  ) async {
    final db = AppDatabase(NativeDatabase.memory());
    await _insertCantiere(db, id: 'c1', name: 'Alfa Chiuso', status: 1);

    await _pumpScreen(tester, db);
    await tester.tap(find.text('CHIUSI'));
    await tester.pumpAndSettle();

    expect(find.text('1 CANTIERE CHIUSO'), findsOneWidget);
    expect(find.text('0 CANTIERI ATTIVI'), findsNothing);

    await db.close();
  });

  testWidgets('renders without overflow at 320px', (tester) async {
    await tester.binding.setSurfaceSize(const Size(320, 700));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final db = AppDatabase(NativeDatabase.memory());
    await _insertCustomer(db, 'cust1', 'Rossi Srl');
    await _insertCantiere(
      db,
      id: 'c1',
      name: 'Ristrutturazione molto lunga di un cantiere in Via Roma',
      customerId: 'cust1',
      city: 'Milano',
      address: 'Via Roma 1',
    );

    await _pumpScreen(tester, db);

    expect(tester.takeException(), isNull);

    await db.close();
  });
}
