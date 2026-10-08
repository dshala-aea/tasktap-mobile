import 'package:drift/drift.dart' show Value, driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tasktap_mobile/data/local/app_database.dart';
import 'package:tasktap_mobile/data/reports/draft_report_repository.dart';
import 'package:tasktap_mobile/data/sync/connectivity_provider.dart';
import 'package:tasktap_mobile/data/sync/sync_service.dart' show appDatabaseProvider;
import 'package:tasktap_mobile/domain/checklist/checklist_items.dart';
import 'package:tasktap_mobile/features/checklist/asset_checklist_screen.dart';
import 'package:tasktap_mobile/features/checklist/control_answer_field.dart';
import 'package:tasktap_mobile/features/checklist/editable_control_tile.dart';
import 'package:tasktap_mobile/presentation/providers/report_editor_providers.dart';

import '../../support/checklist_fixtures.dart';

Widget host(AppDatabase db, {ChecklistFilter filter = ChecklistFilter.all}) => ProviderScope(
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
  child: MaterialApp(home: AssetChecklistScreen(reportId: 'r1', initialFilter: filter)),
);

/// Drift's stream queries schedule a zero-duration timer when their subscription is cancelled
/// (`StreamQueryStore.markAsClosed`), and the riverpod `autoDispose` checklist provider is
/// cancelled when its scope is disposed. Unmounting inside the test body and pumping once lets
/// that timer fire instead of tripping the framework's "A Timer is still pending" assertion at
/// teardown — the same pattern `asset_checklist_screen_test.dart` uses for its drift-backed
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

  testWidgets('answering a row writes it to the editor under the TicketControl id', (tester) async {
    await tester.binding.setSurfaceSize(const Size(400, 1800));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await seedBigTicket(db, assets: 2);
    await tester.pumpWidget(host(db));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Caldaia 1'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Sì').first);
    await tester.pumpAndSettle();

    final container = ProviderScope.containerOf(tester.element(find.byType(AssetChecklistScreen)));
    final row = container.read(reportEditorProvider('r1')).controlloRows.single;
    expect((row.controlId, row.boolValue), ('c-0-0', true));
    await disposeScreen(tester);
  });

  testWidgets('in a filtered view an answered row stays until the filter is applied again, progress is live', (tester) async {
    await tester.binding.setSurfaceSize(const Size(400, 3600));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await seedBigTicket(db, assets: 1);
    await tester.pumpWidget(host(db, filter: ChecklistFilter.toFill));
    await tester.pumpAndSettle();
    expect(find.byType(EditableControlTile), findsNWidgets(15));

    await tester.tap(find.text('Sì').first);
    await tester.pumpAndSettle();

    expect(find.byType(EditableControlTile), findsNWidgets(15), reason: 'the row does not vanish under the thumb');
    expect(find.text('1/15'), findsOneWidget);

    await tester.tap(find.text('Da compilare')); // re-apply the filter
    await tester.pumpAndSettle();
    expect(find.byType(EditableControlTile), findsNWidgets(14));
    await disposeScreen(tester);
  });

  testWidgets('a retained row is shown read-only and marked, never editable', (tester) async {
    await tester.binding.setSurfaceSize(const Size(400, 3600));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await seedBigTicket(db, assets: 1);
    await (db.update(db.ticketControls)..where((c) => c.id.equals('c-0-0'))).write(
      const TicketControlsCompanion(isRetained: Value(true)),
    );
    await tester.pumpWidget(host(db));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Caldaia 1'));
    await tester.pumpAndSettle();

    expect(find.text('Non più richiesto'), findsOneWidget);
    expect(find.byType(ControlAnswerField), findsNWidgets(14));
    await disposeScreen(tester);
  });

  testWidgets('a rapportino without a ticket explains instead of showing an empty list', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          appDatabaseProvider.overrideWithValue(db),
          isOnlineProvider.overrideWithValue(true),
          reportEditorProvider('r1').overrideWith(
            (ref) => ReportEditorNotifier(
              initialState: const ReportEditorState(reportId: 'r1', tenantId: 't', insertedUserId: 'u'),
              repo: DraftReportRepository(db),
            ),
          ),
        ],
        child: const MaterialApp(home: AssetChecklistScreen(reportId: 'r1')),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.textContaining('non è collegato a un ticket'), findsOneWidget);
    await disposeScreen(tester);
  });
}
