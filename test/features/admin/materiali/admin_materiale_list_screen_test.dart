// dart format width=100
// test/features/admin/materiali/admin_materiale_list_screen_test.dart
//
// The redesigned Materiali list: header actions, status chips + Filtri sheet, grouped rows,
// summary, and the stock-free row anatomy. Stock has no local mirror, so nothing here asserts a
// giacenza/sotto-scorta fact; the dropped prototype facts are listed in the task report.

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:tasktap_mobile/data/entitlements/entitlement_providers.dart';
import 'package:tasktap_mobile/data/entitlements/entitlement_repository.dart';
import 'package:tasktap_mobile/data/local/app_database.dart' hide Entitlement;
import 'package:tasktap_mobile/data/sync/sync_service.dart';
import 'package:tasktap_mobile/features/admin/materiali/admin_materiale_list_screen.dart';

AppDatabase _makeDb() => AppDatabase(NativeDatabase.memory());

Widget _buildScreen(AppDatabase db, {Entitlement? entitlement}) {
  return ProviderScope(
    overrides: [
      appDatabaseProvider.overrideWithValue(db),
      if (entitlement != null)
        cachedEntitlementProvider.overrideWith((ref) => Future.value(entitlement)),
    ],
    child: const MaterialApp(home: AdminMaterialeListScreen()),
  );
}

/// A routed harness for the overflow menu's two navigation actions.
Widget _buildRoutedScreen(AppDatabase db) {
  final router = GoRouter(
    initialLocation: '/materiali',
    routes: [
      GoRoute(path: '/materiali', builder: (_, _) => const AdminMaterialeListScreen()),
      GoRoute(
        path: '/altro/magazzino/giacenze',
        builder: (_, _) => const Scaffold(body: Text('giacenze-screen')),
      ),
      GoRoute(
        path: '/altro/magazzino/magazzini',
        builder: (_, _) => const Scaffold(body: Text('magazzini-screen')),
      ),
    ],
  );

  return ProviderScope(
    overrides: [appDatabaseProvider.overrideWithValue(db)],
    child: MaterialApp.router(routerConfig: router),
  );
}

Entitlement _entitlement({Set<String> capabilities = const {}}) => Entitlement(
  features: const {},
  capabilities: capabilities,
  seatType: 'office',
  fetchedAt: DateTime.utc(2026, 9, 23),
);

Future<void> _pump(WidgetTester tester, AppDatabase db, {Entitlement? entitlement}) async {
  await tester.pumpWidget(_buildScreen(db, entitlement: entitlement));
  await tester.pump();
  await tester.pumpAndSettle(const Duration(seconds: 1));
}

Future<void> _tearDownWidget(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pumpAndSettle();
}

Future<void> _seedMateriali(AppDatabase db) async {
  Future<void> add({
    required String id,
    required String code,
    required String name,
    String? category,
    double? salePrice,
    String? description,
    bool active = true,
  }) => db
      .into(db.materiali)
      .insert(
        MaterialiCompanion.insert(
          id: id,
          tenantId: 'tenant-1',
          createdAt: DateTime.utc(2026, 1, 1),
          code: code,
          name: name,
          category: Value(category),
          salePrice: Value(salePrice),
          description: Value(description),
          isActive: Value(active),
        ),
      );

  await add(
    id: 'm1',
    code: 'ART-001',
    name: 'Sifone 40 mm',
    category: 'Idraulica',
    salePrice: 4.20,
    description: 'Sifone in ottone.',
  );
  await add(
    id: 'm2',
    code: 'ART-002',
    name: 'Guarnizione 1/2',
    category: 'Idraulica',
    salePrice: 1.10,
  );
  await add(
    id: 'm3',
    code: 'ART-003',
    name: 'Tubo rame 15',
    category: 'Idraulica',
    salePrice: 6.80,
  );
  await add(
    id: 'm4',
    code: 'ELE-001',
    name: 'Interruttore',
    category: 'Elettrica',
    salePrice: 3.00,
  );
  await add(
    id: 'm5',
    code: 'OLD-001',
    name: 'Raccordo 3/4',
    category: 'Idraulica',
    salePrice: 2.30,
    active: false,
  );
}

void main() {
  late AppDatabase db;

  setUp(() => db = _makeDb());
  tearDown(() async => db.close());

  testWidgets('shows a barcode scan button next to the search bar', (tester) async {
    await _pump(tester, db);

    expect(find.byTooltip('Scansiona codice'), findsOneWidget);

    await _tearDownWidget(tester);
  });

  // An empty mirror is only a statement about the tenant once a sync has landed: before that it
  // says nothing, and the old single message told a fresh install the catalogue did not exist.
  testWidgets('never-synced empty mirror says the catalogue was not downloaded', (tester) async {
    await _pump(tester, db);

    expect(find.text('Catalogo materiali non ancora scaricato'), findsOneWidget);
    expect(find.text('Catalogo materiali vuoto'), findsNothing);

    await _tearDownWidget(tester);
  });

  testWidgets('a synced, genuinely empty catalogue says so instead', (tester) async {
    await db.setLastSync(DateTime.utc(2026, 10, 1));
    await _pump(tester, db);

    expect(find.text('Catalogo materiali vuoto'), findsOneWidget);
    expect(find.text('Catalogo materiali non ancora scaricato'), findsNothing);

    await _tearDownWidget(tester);
  });

  // A search that matched nothing is not a sync problem — it used to send the technician chasing
  // a nonexistent sync issue over a typo.
  testWidgets('a search with no match says no result, not "not downloaded"', (tester) async {
    await _pump(tester, db);

    await tester.enterText(find.byType(TextField), 'bullone inesistente');
    await tester.pumpAndSettle();

    expect(find.text('Nessun risultato'), findsOneWidget);
    expect(find.text('Catalogo materiali non ancora scaricato'), findsNothing);

    await _tearDownWidget(tester);
  });

  testWidgets('renders the prototype title, subtitle and status chips', (tester) async {
    await _seedMateriali(db);
    await _pump(tester, db);

    expect(find.text('Materiali'), findsOneWidget);
    expect(find.text("Cosa c'è, cosa manca, quanto costa."), findsOneWidget);
    expect(find.text('TUTTI'), findsOneWidget);
    expect(find.text('ATTIVI'), findsOneWidget);
    expect(find.text('INATTIVI'), findsOneWidget);
    expect(find.text('FILTRI'), findsOneWidget);

    await _tearDownWidget(tester);
  });

  testWidgets('defaults to active materials and groups Attivi/Inattivi', (tester) async {
    await _seedMateriali(db);
    await _pump(tester, db);

    expect(find.text('Attivi'), findsOneWidget);
    expect(find.text('Inattivi'), findsNothing);
    expect(find.text('Sifone 40 mm'), findsOneWidget);
    expect(find.text('Interruttore'), findsOneWidget);
    expect(find.text('Raccordo 3/4'), findsNothing);

    await _tearDownWidget(tester);
  });

  testWidgets('the overflow menu shows and hides inactive materials', (tester) async {
    await _seedMateriali(db);
    await _pump(tester, db);

    await tester.tap(find.byKey(const Key('materiali-overflow-menu')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Mostra inattivi'));
    await tester.pumpAndSettle();

    expect(find.text('Inattivi'), findsOneWidget);
    expect(find.text('Raccordo 3/4'), findsOneWidget);

    await tester.tap(find.byKey(const Key('materiali-overflow-menu')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Nascondi inattivi'));
    await tester.pumpAndSettle();

    expect(find.text('Inattivi'), findsNothing);
    expect(find.text('Raccordo 3/4'), findsNothing);

    await _tearDownWidget(tester);
  });

  testWidgets('the Tutti chip shows both groups and the summary reports both counts', (
    tester,
  ) async {
    await _seedMateriali(db);
    await _pump(tester, db);

    await tester.tap(find.text('TUTTI'));
    await tester.pumpAndSettle();

    expect(find.text('Attivi'), findsOneWidget);
    expect(find.text('Inattivi'), findsOneWidget);
    expect(find.text('5 MATERIALI'), findsOneWidget);
    expect(find.text('4 ATTIVI'), findsOneWidget);

    await _tearDownWidget(tester);
  });

  testWidgets('the Inattivi chip shows only inactive materials', (tester) async {
    await _seedMateriali(db);
    await _pump(tester, db);

    await tester.tap(find.text('INATTIVI'));
    await tester.pumpAndSettle();

    expect(find.text('Inattivi'), findsOneWidget);
    expect(find.text('Attivi'), findsNothing);
    expect(find.text('Raccordo 3/4'), findsOneWidget);
    expect(find.text('Sifone 40 mm'), findsNothing);

    await _tearDownWidget(tester);
  });

  testWidgets('a row shows code, category, sale price and the active stamp', (tester) async {
    await _seedMateriali(db);
    await _pump(tester, db);

    expect(find.text('ART-001 · Idraulica · € 4,20'), findsOneWidget);
    expect(find.text('ATTIVO'), findsWidgets);

    await _tearDownWidget(tester);
  });

  testWidgets('search matches code, name, category and description', (tester) async {
    await _seedMateriali(db);
    await _pump(tester, db);

    await tester.enterText(find.byType(TextField), 'ART-002');
    await tester.pumpAndSettle();
    expect(find.text('Guarnizione 1/2'), findsOneWidget);
    expect(find.text('Sifone 40 mm'), findsNothing);

    await tester.enterText(find.byType(TextField), 'elettrica');
    await tester.pumpAndSettle();
    expect(find.text('Interruttore'), findsOneWidget);
    expect(find.text('Guarnizione 1/2'), findsNothing);

    await tester.enterText(find.byType(TextField), 'ottone');
    await tester.pumpAndSettle();
    expect(find.text('Sifone 40 mm'), findsOneWidget);
    expect(find.text('Interruttore'), findsNothing);

    await _tearDownWidget(tester);
  });

  testWidgets('the Filtri sheet applies a category and Azzera clears it', (tester) async {
    await _seedMateriali(db);
    await _pump(tester, db);

    await tester.tap(find.text('FILTRI'));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('materiali-filter-category')), findsOneWidget);
    expect(find.byKey(const Key('materiali-filter-status-attivi')), findsOneWidget);

    await tester.tap(find.byKey(const Key('materiali-filter-category')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Elettrica').last);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('materiali-filter-apply')));
    await tester.pumpAndSettle();

    expect(find.text('Interruttore'), findsOneWidget);
    expect(find.text('Sifone 40 mm'), findsNothing);

    await tester.tap(find.text('FILTRI'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('materiali-filter-reset')));
    await tester.pumpAndSettle();

    expect(find.text('Sifone 40 mm'), findsOneWidget);

    await _tearDownWidget(tester);
  });

  testWidgets('the overflow menu hosts the three secondary actions', (tester) async {
    await _seedMateriali(db);

    Future<void> openList() async {
      await tester.pumpWidget(_buildRoutedScreen(db));
      await tester.pumpAndSettle(const Duration(seconds: 1));
    }

    await openList();
    final menu = find.byKey(const Key('materiali-overflow-menu'));
    expect(menu, findsOneWidget);
    expect(tester.getSize(menu).width, greaterThanOrEqualTo(44));
    expect(tester.getSize(menu).height, greaterThanOrEqualTo(44));

    await tester.tap(menu);
    await tester.pumpAndSettle();
    expect(find.text('Giacenze e movimenti'), findsOneWidget);
    expect(find.text('Magazzini'), findsOneWidget);
    expect(find.text('Mostra inattivi'), findsOneWidget);

    await tester.tap(find.text('Giacenze e movimenti'));
    await tester.pumpAndSettle();
    expect(find.text('giacenze-screen'), findsOneWidget);

    await openList();
    await tester.tap(find.byKey(const Key('materiali-overflow-menu')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Magazzini'));
    await tester.pumpAndSettle();
    expect(find.text('magazzini-screen'), findsOneWidget);

    await openList();
    await tester.tap(find.byKey(const Key('materiali-overflow-menu')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Mostra inattivi'));
    await tester.pumpAndSettle();
    expect(find.text('Inattivi'), findsOneWidget);
    expect(find.text('Raccordo 3/4'), findsOneWidget);

    await tester.tap(find.byKey(const Key('materiali-overflow-menu')));
    await tester.pumpAndSettle();
    expect(find.text('Nascondi inattivi'), findsOneWidget);

    await _tearDownWidget(tester);
  });

  testWidgets('Nuovo is hidden without magazzino.article.write', (tester) async {
    await _seedMateriali(db);
    await _pump(
      tester,
      db,
      entitlement: _entitlement(capabilities: const {'magazzino.article.read'}),
    );

    expect(find.text('NUOVO'), findsNothing);

    await _tearDownWidget(tester);
  });

  testWidgets('Nuovo is shown with magazzino.article.write', (tester) async {
    await _seedMateriali(db);
    await _pump(
      tester,
      db,
      entitlement: _entitlement(capabilities: const {'magazzino.article.write'}),
    );

    expect(find.text('NUOVO'), findsOneWidget);

    await _tearDownWidget(tester);
  });

  testWidgets('a long material name clamps instead of overflowing', (tester) async {
    await db
        .into(db.materiali)
        .insert(
          MaterialiCompanion.insert(
            id: 'm-long',
            tenantId: 'tenant-1',
            createdAt: DateTime.utc(2026, 1, 1),
            code: 'LONG-001',
            name:
                'Valvola di intercettazione a sfera con raccordo filettato e leva di '
                'manovra cromata per impianti idraulici',
            category: const Value('Idraulica'),
            salePrice: const Value(12.50),
          ),
        );
    await _pump(tester, db);

    final title = tester.widget<Text>(find.textContaining('Valvola di intercettazione a sfera'));
    expect(title.maxLines, 2);
    expect(title.overflow, TextOverflow.ellipsis);

    await _tearDownWidget(tester);
  });

  testWidgets('renders at 320px without overflowing', (tester) async {
    tester.view.physicalSize = const Size(320, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await _seedMateriali(db);
    await _pump(
      tester,
      db,
      entitlement: _entitlement(capabilities: const {'magazzino.article.write'}),
    );

    expect(find.text('Materiali'), findsOneWidget);
    expect(tester.takeException(), isNull);

    await _tearDownWidget(tester);
  });
}
