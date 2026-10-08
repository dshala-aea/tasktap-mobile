// dart format width=100
import 'checklist_models.dart';
import 'control_type.dart';

/// Backend limits (hand-off 2.1): note <= 2000 characters, assets x controls <= 5000.
const int kBulkNoteMax = 2000;
const int kBulkMaxPairs = 5000;

class BulkRequest {
  const BulkRequest({
    required this.assetIds,
    required this.lineageIds,
    this.boolValue,
    this.appendNote,
  });

  final Set<String> assetIds;

  /// `controlLineageId`s: the version-independent selector (assets pinned to different template
  /// versions of the same control are selected together).
  final Set<String> lineageIds;

  /// Set on Checkbox/TrueFalse controls only.
  final bool? boolValue;

  /// Appended, never overwriting, on any control type.
  final String? appendNote;
}

enum BulkProblemCode { emptyAction, noSelection, tooLarge, noteTooLong }

class BulkProblem {
  const BulkProblem({required this.code, this.assetId, this.lineageId});
  final BulkProblemCode code;
  final String? assetId;
  final String? lineageId;
}

class BulkChange {
  const BulkChange({required this.control, required this.previous, required this.next});
  final ChecklistControl control;

  /// The local row before the bulk, or null when there was none (undo removes it then).
  final ChecklistAnswer? previous;
  final ChecklistAnswer next;
}

class BulkPlan {
  const BulkPlan({
    this.changes = const [],
    this.skippedNonBoolean = 0,
    this.notApplicable = 0,
    this.problems = const [],
    this.rejected = false,
  });

  factory BulkPlan.rejected(BulkProblem problem) =>
      BulkPlan(problems: [problem], rejected: true);

  final List<BulkChange> changes;
  final int skippedNonBoolean;
  final int notApplicable;
  final List<BulkProblem> problems;

  /// The whole request was refused (nothing to do, nothing selected, too large).
  final bool rejected;

  int get affected => changes.length;
}

bool _usesString(ControlType t) =>
    t == ControlType.text || t == ControlType.options || t == ControlType.unknown;

/// Plans a bulk action over assets x lineages against the materialised rows, without writing
/// anything. Mirrors the backend rules; a pair that does not apply is skipped and counted (the
/// phone never rejects the whole request, see the task intro).
BulkPlan planBulk({
  required BulkRequest request,
  required TicketChecklist tree,
  required Map<String, ChecklistAnswer> existing,
}) {
  final raw = request.appendNote?.trim();
  final note = (raw == null || raw.isEmpty) ? null : raw;
  if (request.boolValue == null && note == null) {
    return BulkPlan.rejected(const BulkProblem(code: BulkProblemCode.emptyAction));
  }
  if (request.assetIds.isEmpty || request.lineageIds.isEmpty) {
    return BulkPlan.rejected(const BulkProblem(code: BulkProblemCode.noSelection));
  }
  // Checked before any pair work, like the backend's selection_too_large.
  if (request.assetIds.length * request.lineageIds.length > kBulkMaxPairs) {
    return BulkPlan.rejected(const BulkProblem(code: BulkProblemCode.tooLarge));
  }

  final assets = {for (final a in tree.distinctAssets) a.assetId: a};
  final changes = <BulkChange>[];
  final problems = <BulkProblem>[];
  var skippedNonBoolean = 0;
  var notApplicable = 0;

  for (final assetId in request.assetIds) {
    final asset = assets[assetId];
    if (asset == null || !asset.templated || !asset.coveredNow) {
      notApplicable += request.lineageIds.length;
      continue;
    }
    final byLineage = {
      for (final c in asset.controls)
        if (!c.isRetained) c.lineageId: c,
    };
    for (final lineage in request.lineageIds) {
      final control = byLineage[lineage];
      if (control == null) {
        notApplicable++;
        continue;
      }
      if (request.boolValue != null && !isBooleanControl(control.type)) {
        skippedNonBoolean++;
        continue;
      }
      final previous = existing[control.id];
      final base = previous ?? control.stored;
      var nextNote = base.hasNote ? base.note!.trim() : null;
      if (note != null) {
        final combined = nextNote == null ? note : '$nextNote\n$note';
        if (combined.length > kBulkNoteMax) {
          problems.add(BulkProblem(code: BulkProblemCode.noteTooLong, assetId: assetId, lineageId: lineage));
          continue;
        }
        nextNote = combined;
      }
      // A control whose wire type this build does not recognise could hold its answer in ANY
      // column (ChecklistAnswer.answers(unknown) accepts them all), and a boolean bulk never
      // reaches this point for one (see the isBooleanControl guard above). So an unknown-type row
      // keeps every column it had and only gains the note: narrowing it to the string column would
      // silently destroy a stored number/date/boolean answer, the exact opposite of this module's
      // "append, never overwrite" rule.
      final unknown = control.type == ControlType.unknown;
      changes.add(
        BulkChange(
          control: control,
          previous: previous,
          next: ChecklistAnswer(
            stringValue: _usesString(control.type) ? base.stringValue : null,
            boolValue: unknown
                ? base.boolValue
                : (isBooleanControl(control.type) ? (request.boolValue ?? base.boolValue) : null),
            dateValue: unknown
                ? base.dateValue
                : (control.type == ControlType.dateTime ? base.dateValue : null),
            numberValue: unknown
                ? base.numberValue
                : (control.type == ControlType.number ? base.numberValue : null),
            note: nextNote,
          ),
        ),
      );
    }
  }
  return BulkPlan(
    changes: changes,
    skippedNonBoolean: skippedNonBoolean,
    notApplicable: notApplicable,
    problems: problems,
  );
}

class BulkLineageOption {
  const BulkLineageOption({
    required this.lineageId,
    required this.label,
    required this.isBoolean,
    required this.assetCount,
  });

  final String lineageId;
  final String label;
  final bool isBoolean;

  /// How many of the scoped assets have this control.
  final int assetCount;
}

/// The controls a bulk action can target for [scopeAssetIds], in label order.
List<BulkLineageOption> bulkLineageOptions(TicketChecklist tree, Set<String> scopeAssetIds) {
  final labels = <String, String>{};
  final booleans = <String, bool>{};
  final counts = <String, int>{};
  for (final a in tree.distinctAssets) {
    if (!scopeAssetIds.contains(a.assetId) || !a.templated || !a.coveredNow) continue;
    final seen = <String>{};
    for (final c in a.controls) {
      if (c.isRetained || !seen.add(c.lineageId)) continue;
      labels.putIfAbsent(c.lineageId, () => c.label);
      booleans[c.lineageId] = (booleans[c.lineageId] ?? true) && isBooleanControl(c.type);
      counts[c.lineageId] = (counts[c.lineageId] ?? 0) + 1;
    }
  }
  final ids = labels.keys.toList()..sort((x, y) => naturalCompare(labels[x]!, labels[y]!));
  return [
    for (final id in ids)
      BulkLineageOption(
        lineageId: id,
        label: labels[id]!,
        isBoolean: booleans[id]!,
        assetCount: counts[id]!,
      ),
  ];
}

String describeBulkProblem(BulkProblem p, {int count = 1}) {
  switch (p.code) {
    case BulkProblemCode.emptyAction:
      return 'Scegli un\'azione: segna come controllato oppure aggiungi una nota.';
    case BulkProblemCode.noSelection:
      return 'Scegli almeno un asset e un controllo.';
    case BulkProblemCode.tooLarge:
      return 'La selezione è troppo grande: al massimo $kBulkMaxPairs righe per volta.';
    case BulkProblemCode.noteTooLong:
      return 'La nota supera $kBulkNoteMax caratteri su $count righe: accorciala.';
  }
}
