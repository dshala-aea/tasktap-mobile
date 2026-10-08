import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tasktap_mobile/data/local/app_database.dart';
import 'package:tasktap_mobile/data/reports/draft_report_repository.dart';
import 'package:tasktap_mobile/domain/checklist/bulk_actions.dart';
import 'package:tasktap_mobile/domain/checklist/checklist_models.dart';
import 'package:tasktap_mobile/domain/checklist/control_type.dart';
import 'package:tasktap_mobile/features/checklist/bulk_executor.dart';
import 'package:tasktap_mobile/presentation/providers/report_editor_providers.dart';

void main() {
  late AppDatabase db;
  late ReportEditorNotifier notifier;

  setUp(() async {
    driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
    db = AppDatabase(NativeDatabase.memory());
    notifier = ReportEditorNotifier(
      initialState: const ReportEditorState(reportId: 'r1', tenantId: 't', insertedUserId: 'u'),
      repo: DraftReportRepository(db),
    );
    await notifier.ready;
  });
  tearDown(() => db.close());

  TicketChecklist big() => TicketChecklist(
    ticketId: 't1',
    standalone: [
      for (var a = 0; a < 200; a++)
        AssetChecklist(
          assetId: 'a$a', name: 'Asset $a', templated: true,
          groups: [
            ChecklistGroup(id: 'g', name: 'G', controls: [
              for (var k = 0; k < 15; k++)
                ChecklistControl(
                  id: 'c-$a-$k', ticketId: 't1', assetId: 'a$a', templateControlId: 'tc-$k', lineageId: 'l$k',
                  groupId: 'g', label: 'L$k', type: k < 10 ? ControlType.checkbox : ControlType.number,
                ),
            ]),
          ],
        ),
    ],
  );

  test('200 x 10 booleans are written in one pass and one state update', () async {
    final plan = planBulk(
      request: BulkRequest(
        assetIds: {for (var a = 0; a < 200; a++) 'a$a'},
        lineageIds: {for (var k = 0; k < 10; k++) 'l$k'},
        boolValue: true,
      ),
      tree: big(),
      existing: const {},
    );
    var emissions = 0;
    final sub = notifier.addListener((_) => emissions++, fireImmediately: false);

    await BulkExecutor(notifier, 'r1').apply(plan);
    sub();

    expect(emissions, 1, reason: 'a single state update, not 2000');
    expect(notifier.state.controlloRows.length, 2000);
    expect((await db.select(db.reportControlli).get()).length, 2000);
    expect(notifier.state.controlloRows.first.id, 'ctrl-r1-c-0-0');
    expect(notifier.state.controlloRows.every((r) => r.boolValue == true), isTrue);
  });

  test('rows the bulk did not touch survive, touched ones are replaced', () async {
    await notifier.upsertControllo(
      const ControlloRow(id: 'ctrl-r1-c-0-0', reportId: 'r1', controlId: 'c-0-0', boolValue: false),
    );
    await notifier.upsertControllo(
      const ControlloRow(id: 'ctrl-r1-c-5-12', reportId: 'r1', controlId: 'c-5-12', numberValue: 7),
    );
    final plan = planBulk(
      request: const BulkRequest(assetIds: {'a0'}, lineageIds: {'l0'}, boolValue: true),
      tree: big(),
      existing: {'c-0-0': const ChecklistAnswer(boolValue: false)},
    );

    await BulkExecutor(notifier, 'r1').apply(plan);

    final byId = {for (final r in notifier.state.controlloRows) r.id: r};
    expect(byId['ctrl-r1-c-0-0']!.boolValue, true);
    expect(byId['ctrl-r1-c-5-12']!.numberValue, 7);
  });

  test('undo restores the previous rows and removes the ones that did not exist', () async {
    await notifier.upsertControllo(
      const ControlloRow(id: 'ctrl-r1-c-0-0', reportId: 'r1', controlId: 'c-0-0', boolValue: false, note: 'prima'),
    );
    final plan = planBulk(
      request: const BulkRequest(assetIds: {'a0', 'a1'}, lineageIds: {'l0'}, boolValue: true),
      tree: big(),
      existing: {'c-0-0': const ChecklistAnswer(boolValue: false, note: 'prima')},
    );
    final exec = BulkExecutor(notifier, 'r1');

    await exec.apply(plan);
    expect(notifier.state.controlloRows.length, 2);
    await exec.undo(plan);

    final rows = notifier.state.controlloRows;
    expect(rows.single.id, 'ctrl-r1-c-0-0');
    expect((rows.single.boolValue, rows.single.note), (false, 'prima'));
    final db0 = await db.select(db.reportControlli).get();
    expect(db0.single.id, 'ctrl-r1-c-0-0');
  });

  test('a rejected plan changes nothing', () async {
    final plan = planBulk(
      request: const BulkRequest(assetIds: {'a0'}, lineageIds: {'l0'}),
      tree: big(),
      existing: const {},
    );
    await BulkExecutor(notifier, 'r1').apply(plan);
    expect(notifier.state.controlloRows, isEmpty);
  });
}
