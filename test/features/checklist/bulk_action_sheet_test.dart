import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tasktap_mobile/core/icons/app_lucide_icons.dart';
import 'package:tasktap_mobile/data/local/app_database.dart';
import 'package:tasktap_mobile/data/reports/draft_report_repository.dart';
import 'package:tasktap_mobile/data/sync/connectivity_provider.dart';
import 'package:tasktap_mobile/data/sync/sync_service.dart' show appDatabaseProvider;
import 'package:tasktap_mobile/features/checklist/asset_checklist_screen.dart';
import 'package:tasktap_mobile/presentation/providers/report_editor_providers.dart';

import '../../support/checklist_fixtures.dart';

Widget host(AppDatabase db) => ProviderScope(
  overrides: [
    appDatabaseProvider.overrideWithValue(db),
    isOnlineProvider.overrideWithValue(true),
    reportEditorProvider('r1').overrideWith(
      (ref) => ReportEditorNotifier(
        initialState: const ReportEditorState(reportId: 'r1', tenantId: 't', insertedUserId: 'u', ticketId: 't1'),
        repo: DraftReportRepository(db),
      ),
    ),
  ],
  child: const MaterialApp(home: AssetChecklistScreen(reportId: 'r1')),
);

/// Drift's stream queries schedule a zero-duration timer when their subscription is cancelled
/// (`StreamQueryStore.markAsClosed`), and the riverpod `autoDispose` checklist provider is
/// cancelled when its scope is disposed. Unmounting inside the test body and pumping once lets
/// that timer fire instead of tripping the framework's "A Timer is still pending" assertion at
/// teardown — the same pattern `asset_checklist_editing_test.dart` uses for its drift-backed
/// providers.
Future<void> disposeScreen(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pumpAndSettle();
}

void main() {
  late AppDatabase db;

  setUp(() {
    driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
    db = AppDatabase(NativeDatabase.memory());
  });
  tearDown(() => db.close());

  List<ControlloRow> rows(WidgetTester tester) => ProviderScope.containerOf(
    tester.element(find.byType(AssetChecklistScreen)),
  ).read(reportEditorProvider('r1')).controlloRows;

  testWidgets('read-only ticket view has no bulk action', (tester) async {
    await seedBigTicket(db, assets: 2);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [appDatabaseProvider.overrideWithValue(db), isOnlineProvider.overrideWithValue(true)],
        child: const MaterialApp(home: AssetChecklistScreen(ticketId: 't1')),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byIcon(LucideIcons.checkCircle2), findsNothing);

    await disposeScreen(tester);
  });

  testWidgets('"Segna controllato" on one control writes a row per shown asset, with a one-tap undo', (tester) async {
    await tester.binding.setSurfaceSize(const Size(400, 1800));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await seedBigTicket(db, assets: 5);
    await tester.pumpWidget(host(db));
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(LucideIcons.checkCircle2));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Controllo 0'));
    await tester.pumpAndSettle();
    expect(find.textContaining('5 asset'), findsWidgets, reason: 'the preview names what will change');

    await tester.tap(find.text('Applica'));
    await tester.pumpAndSettle();

    expect(rows(tester).length, 5);
    expect(rows(tester).every((r) => r.boolValue == true && r.controlId.endsWith('-0')), isTrue);

    await tester.tap(find.text('Annulla'));
    await tester.pumpAndSettle();
    expect(rows(tester), isEmpty);

    await disposeScreen(tester);
  });

  testWidgets('"Aggiungi nota" appends the note to every selected row without answering it', (tester) async {
    await tester.binding.setSurfaceSize(const Size(400, 1800));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await seedBigTicket(db, assets: 3);
    await tester.pumpWidget(host(db));
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(LucideIcons.checkCircle2));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Aggiungi nota'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Controllo 10')); // a Number control: a note is allowed on any type
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).last, 'manometro verificato');
    await tester.pumpAndSettle();
    await tester.tap(find.text('Applica'));
    await tester.pumpAndSettle();

    final written = rows(tester);
    expect(written.length, 3);
    expect(written.every((r) => r.note == 'manometro verificato' && r.numberValue == null), isTrue);

    await disposeScreen(tester);
  });

  testWidgets('"Segna controllato" only offers boolean controls', (tester) async {
    await tester.binding.setSurfaceSize(const Size(400, 1800));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await seedBigTicket(db, assets: 2);
    await tester.pumpWidget(host(db));
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(LucideIcons.checkCircle2));
    await tester.pumpAndSettle();

    expect(find.text('Controllo 0'), findsOneWidget);
    expect(find.text('Controllo 10'), findsNothing, reason: 'a Number control cannot be "set"');

    await disposeScreen(tester);
  });
}
