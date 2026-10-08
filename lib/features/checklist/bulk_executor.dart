// dart format width=100
import '../../data/reports/import_server_report.dart' show controlRowId;
import '../../domain/checklist/bulk_actions.dart';
import '../../domain/checklist/checklist_models.dart';
import '../../presentation/providers/report_editor_providers.dart';

/// Applies a [BulkPlan] to the rapportino's local answers, and takes it back.
class BulkExecutor {
  BulkExecutor(this._notifier, this.reportId);

  final ReportEditorNotifier _notifier;
  final String reportId;

  ControlloRow _row(ChecklistControl c, ChecklistAnswer a) => ControlloRow(
    id: controlRowId(reportId, c.id),
    reportId: reportId,
    controlId: c.id,
    stringValue: a.stringValue,
    boolValue: a.boolValue,
    dateValue: a.dateValue,
    numberValue: a.numberValue,
    note: a.note,
  );

  Future<void> apply(BulkPlan plan) {
    if (plan.rejected || plan.changes.isEmpty) return Future.value();
    return _notifier.applyControlloRows([for (final c in plan.changes) _row(c.control, c.next)]);
  }

  /// Restores every previous row and removes the rows the bulk created.
  Future<void> undo(BulkPlan plan) async {
    if (plan.rejected || plan.changes.isEmpty) return;
    final restore = [
      for (final c in plan.changes)
        if (c.previous != null) _row(c.control, c.previous!),
    ];
    final remove = [
      for (final c in plan.changes)
        if (c.previous == null) controlRowId(reportId, c.control.id),
    ];
    await _notifier.removeControlloRows(remove);
    await _notifier.applyControlloRows(restore);
  }
}
