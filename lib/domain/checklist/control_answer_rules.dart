// dart format width=100
import 'package:intl/intl.dart';

import 'checklist_models.dart';
import 'control_type.dart';

/// The answer to show and to judge: a local row replaces the server's stored one entirely (the
/// editor copies the stored values into the row on first interaction, see `ControlAnswerField`).
ChecklistAnswer effectiveAnswer(ChecklistControl c, ChecklistAnswer? local) => local ?? c.stored;

/// Server rule mirrored: the column that matches the type holds a value, OR the ticket already
/// holds the answer (multi-visit). A note is never an answer.
bool isAnswered(ChecklistControl c, ChecklistAnswer? local) =>
    (local?.answers(c.type) ?? false) || c.serverHoldsAnswer;

/// Product definition (plan "Resolved ambiguities" 5): a boolean answered false, or any non-blank
/// note. The "Eccezioni" filter shows exactly these.
bool isException(ChecklistControl c, ChecklistAnswer? local) {
  final a = effectiveAnswer(c, local);
  return (isBooleanControl(c.type) && a.boolValue == false) || a.hasNote;
}

class AssetProgress {
  const AssetProgress({
    required this.total,
    required this.answered,
    required this.requiredMissing,
    required this.exceptions,
  });

  final int total;
  final int answered;
  final int requiredMissing;
  final int exceptions;

  bool get complete => answered == total;
}

/// Retained rows (the server no longer lists them) are not part of progress: the gate ignores them.
AssetProgress progressOf(
  Iterable<ChecklistControl> controls,
  ChecklistAnswer? Function(String controlId) local,
) {
  var total = 0;
  var answered = 0;
  var missing = 0;
  var exceptions = 0;
  for (final c in controls) {
    if (c.isRetained) continue;
    total++;
    final a = local(c.id);
    final done = isAnswered(c, a);
    if (done) answered++;
    if (!done && c.isRequired) missing++;
    if (isException(c, a)) exceptions++;
  }
  return AssetProgress(total: total, answered: answered, requiredMissing: missing, exceptions: exceptions);
}

/// A short human value of [a] for [c], or null when that type's column is empty.
String? describeAnswer(ChecklistControl c, ChecklistAnswer a) {
  switch (c.type) {
    case ControlType.checkbox:
    case ControlType.trueFalse:
      return a.boolValue == null ? null : (a.boolValue! ? 'Sì' : 'No');
    case ControlType.number:
      final v = a.numberValue;
      if (v == null) return null;
      return v == v.roundToDouble() ? v.toStringAsFixed(0) : v.toString();
    case ControlType.dateTime:
      final d = a.dateValue;
      // Same convention as the ticket-level checklist: the picker yields a local date, shown local.
      return d == null ? null : DateFormat('dd/MM/yyyy').format(d.toLocal());
    case ControlType.text:
    case ControlType.options:
    case ControlType.unknown:
      final s = (a.stringValue ?? '').trim();
      return s.isEmpty ? null : s;
  }
}
