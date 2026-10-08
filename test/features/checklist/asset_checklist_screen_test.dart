import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tasktap_mobile/data/local/app_database.dart';
import 'package:tasktap_mobile/data/sync/connectivity_provider.dart';
import 'package:tasktap_mobile/data/sync/sync_service.dart' show appDatabaseProvider;
import 'package:tasktap_mobile/features/checklist/asset_checklist_screen.dart';
import 'package:tasktap_mobile/features/checklist/checklist_providers.dart';

import '../../support/checklist_fixtures.dart';

Widget host(AppDatabase db, {bool online = true, Future<void> Function(String)? backfill}) => ProviderScope(
  overrides: [
    appDatabaseProvider.overrideWithValue(db),
    isOnlineProvider.overrideWithValue(online),
    if (backfill != null) checklistBackfillProvider.overrideWithValue(backfill),
  ],
  child: const MaterialApp(home: AssetChecklistScreen(ticketId: 't1')),
);

/// Drift's stream queries schedule a zero-duration timer when their subscription is cancelled
/// (`StreamQueryStore.markAsClosed`) and the riverpod `autoDispose` checklist provider is cancelled
/// when its scope is disposed. Unmounting inside the test body and pumping once lets that timer
/// fire, instead of tripping the framework's "A Timer is still pending" assertion at teardown —
/// the same pattern `dashboard_screen_test.dart` uses for its own drift-backed providers.
Future<void> disposeScreen(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pumpAndSettle();
}

/// The filter chips live in a horizontally scrolling [ListView] and do not all fit the test
/// surface: the trailing ones are not even built until the row is scrolled (a `SliverChildList`
/// builds only the viewport plus its cache extent). Bring the chip into view — scrolling the
/// horizontal list first when it does not exist yet — before tapping it by label.
Future<void> tapChip(WidgetTester tester, String label) async {
  final chip = find.text(label);
  if (chip.evaluate().isEmpty) {
    await tester.scrollUntilVisible(
      chip,
      120,
      // Only the filter row is a ListView (the search field's own horizontal scroll view is not),
      // so this picks the row unambiguously.
      scrollable: find.descendant(
        of: find.byType(ListView),
        matching: find.byType(Scrollable),
      ),
      maxScrolls: 20,
    );
  }
  await tester.ensureVisible(chip);
  await tester.pumpAndSettle();
  await tester.tap(chip);
  await tester.pumpAndSettle();
}

void main() {
  late AppDatabase db;

  setUp(() {
    driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
    db = AppDatabase(NativeDatabase.memory());
  });
  tearDown(() => db.close());

  testWidgets('shows the libretto, its children collapsed with progress, offline', (tester) async {
    await seedBigTicket(db, assets: 3);
    await tester.pumpWidget(host(db, online: false));
    await tester.pumpAndSettle();

    expect(find.text('Libretto Nord'), findsWidgets);
    expect(find.text('Caldaia 1'), findsOneWidget);
    expect(find.text('Caldaia 3'), findsOneWidget);
    expect(find.text('0/15'), findsNWidgets(3), reason: 'answered / total per asset');
    expect(find.byType(ControlItemTile), findsNothing, reason: 'collapsed by default');
    await disposeScreen(tester);
  });

  testWidgets('tapping an asset expands its checklist', (tester) async {
    await seedBigTicket(db, assets: 3);
    await tester.pumpWidget(host(db));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Caldaia 2'));
    await tester.pumpAndSettle();

    expect(find.byType(ControlItemTile), findsWidgets);
    expect(find.text('Sicurezza'), findsOneWidget);
    await disposeScreen(tester);
  });

  /// 3000 rows must not become 3000 widgets: this is the failure that freezes a phone.
  testWidgets('windowed: fewer than 60 tiles are built for 3000 rows, and the end is reachable', (tester) async {
    await tester.binding.setSurfaceSize(const Size(400, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await seedBigTicket(db);
    await tester.pumpWidget(host(db));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Da compilare')); // auto-expands every asset: 3000 control rows
    await tester.pumpAndSettle();

    expect(find.byType(ControlItemTile).evaluate().length, lessThan(60));

    await tester.scrollUntilVisible(
      find.text('Caldaia 200'),
      20000,
      scrollable: find.byType(Scrollable).last,
      maxScrolls: 400,
    );
    expect(find.text('Caldaia 200'), findsOneWidget);
    expect(find.byType(ControlItemTile).evaluate().length, lessThan(60));
    await disposeScreen(tester);
  });

  testWidgets('Obbligatori mancanti shows only assets with required rows left', (tester) async {
    // Tall enough that the lazy list builds all ten rows.
    await tester.binding.setSurfaceSize(const Size(400, 1800));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await seedBigTicket(db, assets: 2);
    await tester.pumpWidget(host(db));
    await tester.pumpAndSettle();

    await tapChip(tester, 'Obbligatori mancanti');

    expect(find.byType(ControlItemTile), findsNWidgets(10), reason: '2 assets x 5 required controls');
    await disposeScreen(tester);
  });

  testWidgets('the Eccezioni filter explains itself when nothing is an exception', (tester) async {
    await seedBigTicket(db, assets: 2);
    await tester.pumpWidget(host(db));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Eccezioni'));
    await tester.pumpAndSettle();

    expect(find.byType(ControlItemTile), findsNothing);
    expect(find.text('Nessun elemento'), findsOneWidget);
    await disposeScreen(tester);
  });

  testWidgets('searching by matricola narrows the list', (tester) async {
    await seedBigTicket(db, assets: 5);
    await tester.pumpWidget(host(db));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField).first, 'M-1003');
    await tester.pumpAndSettle();

    expect(find.text('Caldaia 4'), findsOneWidget);
    expect(find.text('Caldaia 1'), findsNothing);
    await disposeScreen(tester);
  });

  testWidgets('Per controllo groups one control across all assets', (tester) async {
    await seedBigTicket(db, assets: 3);
    await tester.pumpWidget(host(db));
    await tester.pumpAndSettle();

    await tapChip(tester, 'Per controllo');

    expect(find.text('Controllo 0'), findsWidgets);
    expect(find.textContaining('3 asset'), findsWidgets);
    await disposeScreen(tester);
  });

  testWidgets('an omitted ticket shows a banner and a working "Scarica checklist" button', (tester) async {
    await db.into(db.checklistOmittedTickets).insert(ChecklistOmittedTicketsCompanion.insert(ticketId: 't1'));
    final asked = <String>[];
    await tester.pumpWidget(host(db, backfill: (id) async => asked.add(id)));
    await tester.pumpAndSettle();

    expect(find.textContaining('non è ancora scaricata'), findsOneWidget);
    await tester.tap(find.text('Scarica checklist'));
    await tester.pumpAndSettle();

    expect(asked, ['t1']);
    await disposeScreen(tester);
  });

  testWidgets('offline, the omitted banner explains and the button is disabled', (tester) async {
    await db.into(db.checklistOmittedTickets).insert(ChecklistOmittedTicketsCompanion.insert(ticketId: 't1'));
    await tester.pumpWidget(host(db, online: false, backfill: (_) async {}));
    await tester.pumpAndSettle();

    expect(find.textContaining('Collegati a internet'), findsOneWidget);
    await disposeScreen(tester);
  });
}
