// dart format width=100
// test/features/checklist/check_all_booleans_test.dart
//
// "Spunta tutti" per asset: the rule (which rows it may touch) and the button that fires it.

import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:tasktap_mobile/data/local/app_database.dart';
import 'package:tasktap_mobile/data/reports/draft_report_repository.dart';
import 'package:tasktap_mobile/data/reports/import_server_report.dart' show controlRowId;
import 'package:tasktap_mobile/data/sync/connectivity_provider.dart';
import 'package:tasktap_mobile/data/sync/sync_service.dart' show appDatabaseProvider;
import 'package:tasktap_mobile/domain/checklist/checklist_models.dart';
import 'package:tasktap_mobile/domain/checklist/control_type.dart';
import 'package:tasktap_mobile/features/checklist/asset_checklist_screen.dart';
import 'package:tasktap_mobile/features/checklist/check_all_booleans.dart';
import 'package:tasktap_mobile/presentation/providers/report_editor_providers.dart';

import '../../support/checklist_fixtures.dart';

ChecklistControl control(
  String id,
  ControlType type, {
  bool retained = false,
  String label = 'Controllo',
}) => ChecklistControl(
  id: id,
  ticketId: 't1',
  assetId: 'a1',
  templateControlId: 'tc-$id',
  lineageId: 'l-$id',
  groupId: 'g1',
  label: label,
  type: type,
  isRetained: retained,
);

AssetChecklist assetWith(List<ChecklistControl> controls) => AssetChecklist(
  assetId: 'a1',
  name: 'Caldaia 1',
  templated: true,
  groups: [ChecklistGroup(id: 'g1', name: 'Sicurezza', controls: controls)],
);

void main() {
  setUpAll(() => driftRuntimeOptions.dontWarnAboutMultipleDatabases = true);

  group('planCheckAllBooleans', () {
    test('ticks every boolean control and leaves the other types alone', () {
      final asset = assetWith([
        control('c1', ControlType.checkbox),
        control('c2', ControlType.trueFalse),
        control('c3', ControlType.number),
        control('c4', ControlType.text),
        control('c5', ControlType.dateTime),
        control('c6', ControlType.options),
      ]);
      final rows = planCheckAllBooleans('r1', asset, const {});
      expect(rows.map((r) => r.controlId), ['c1', 'c2']);
      expect(rows.every((r) => r.boolValue == true), isTrue);
      expect(rows.first.id, controlRowId('r1', 'c1'));
      expect(rows.first.reportId, 'r1');
    });

    test('skips a control already ticked, so a summary does not overcount', () {
      final asset = assetWith([
        control('c1', ControlType.checkbox),
        control('c2', ControlType.checkbox),
      ]);
      final rows = planCheckAllBooleans('r1', asset, const {
        'c1': ChecklistAnswer(boolValue: true),
      });
      expect(rows.map((r) => r.controlId), ['c2']);
    });

    test('a retained control is skipped: the server no longer sends that row', () {
      final asset = assetWith([
        control('c1', ControlType.checkbox, retained: true),
        control('c2', ControlType.checkbox),
      ]);
      expect(planCheckAllBooleans('r1', asset, const {}).map((r) => r.controlId), ['c2']);
    });

    test('ticking a row that carries a note keeps the note', () {
      final asset = assetWith([control('c1', ControlType.checkbox)]);
      final rows = planCheckAllBooleans('r1', asset, const {
        'c1': ChecklistAnswer(boolValue: false, note: 'perdita dalla guarnizione'),
      });
      expect(rows.single.boolValue, isTrue);
      expect(rows.single.note, 'perdita dalla guarnizione');
    });

    test('an asset with no boolean control plans nothing', () {
      final asset = assetWith([control('c1', ControlType.number)]);
      expect(planCheckAllBooleans('r1', asset, const {}), isEmpty);
    });
  });

  group('the button', () {
    late AppDatabase db;
    setUp(() => db = AppDatabase(NativeDatabase.memory()));
    tearDown(() => db.close());

    Widget host() => ProviderScope(
      overrides: [
        appDatabaseProvider.overrideWithValue(db),
        isOnlineProvider.overrideWithValue(true),
        reportEditorProvider('r1').overrideWith(
          (ref) => ReportEditorNotifier(
            initialState: const ReportEditorState(
              reportId: 'r1',
              tenantId: 't',
              insertedUserId: 'u',
              ticketId: 't1',
            ),
            repo: DraftReportRepository(db),
          ),
        ),
      ],
      child: const MaterialApp(home: AssetChecklistScreen(reportId: 'r1')),
    );

    testWidgets('ticks the asset\'s ten check controls in one tap, without expanding it', (
      tester,
    ) async {
      await tester.binding.setSurfaceSize(const Size(400, 2400));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await seedBigTicket(db, assets: 1);
      await tester.pumpWidget(host());
      await tester.pumpAndSettle();

      expect(find.text('Spunta tutti'), findsOneWidget);
      await tester.tap(find.text('Spunta tutti'));
      await tester.pumpAndSettle();

      final container = ProviderScope.containerOf(
        tester.element(find.byType(AssetChecklistScreen)),
      );
      final rows = container.read(reportEditorProvider('r1')).controlloRows;
      expect(rows, hasLength(10), reason: 'k 0-9 are Checkbox, the rest are not boolean');
      expect(rows.every((r) => r.boolValue == true), isTrue);
      expect(rows.map((r) => r.controlId).toSet(), {for (var k = 0; k < 10; k++) 'c-0-$k'});
      expect(find.text('10/15'), findsOneWidget, reason: 'the header progress follows');

      // Unmount before teardown so the autoDispose drift streams' zero-duration timer fires.
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
    });
  });
}
