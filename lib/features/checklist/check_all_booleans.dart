// dart format width=100
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/reports/import_server_report.dart' show controlRowId;
import '../../domain/checklist/checklist_models.dart';
import '../../domain/checklist/control_type.dart' show isBooleanControl;
import '../../presentation/providers/report_editor_providers.dart';
import 'checklist_providers.dart' show controlAnswersProvider;

/// "Spunta tutti": every check/true-false control of ONE asset, ticked.
///
/// Mirrors the web report editor's per-card button (`checkAllBooleans` in its answer store), so a
/// technician facing fifteen identical checklist rows on a phone does not tap fifteen times.
///
/// [planCheckAllBooleans] is the rule; [checkAllBooleans] writes it. The rule is deliberately
/// narrow, because a bulk tick must never quietly undo work:
///  - only this asset's controls, and only boolean ones — a text/number/date answer is untouched;
///  - a control already ticked is skipped, so it stays clean and a summary does not lie;
///  - a retained control is skipped (`isRetained`): the server stopped sending that row, and the
///    screen shows it read-only for the same reason;
///  - an existing note on the row is carried over — ticking must not erase what was written
///    about it.
///
/// Nothing is sent: the rows land in the local draft exactly like a tap on the control, and the
/// report's own save/queue path carries them.
List<ControlloRow> planCheckAllBooleans(
  String reportId,
  AssetChecklist asset,
  Map<String, ChecklistAnswer> existing,
) {
  final rows = <ControlloRow>[];
  for (final c in asset.controls) {
    if (c.isRetained || !isBooleanControl(c.type)) continue;
    final current = existing[c.id];
    if (current?.boolValue == true) continue;
    rows.add(
      ControlloRow(
        id: controlRowId(reportId, c.id),
        reportId: reportId,
        controlId: c.id,
        boolValue: true,
        // A note is not itself an answer, and ticking does not make it one.
        note: current?.hasNote == true ? current!.note : null,
      ),
    );
  }
  return rows;
}

/// Applies [planCheckAllBooleans] to one asset in a single state update and Drift batch.
/// Returns how many controls changed (0 when there was nothing left to tick).
Future<int> checkAllBooleans(WidgetRef ref, String reportId, AssetChecklist asset) async {
  final rows = planCheckAllBooleans(reportId, asset, ref.read(controlAnswersProvider(reportId)));
  if (rows.isEmpty) return 0;
  await ref.read(reportEditorProvider(reportId).notifier).applyControlloRows(rows);
  return rows.length;
}
