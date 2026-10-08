// dart format width=100
import 'package:flutter/material.dart';

import '../../../core/widgets/inline_alert.dart';
import 'package:tasktap_mobile/core/icons/app_lucide_icons.dart';
import 'package:tasktap_mobile/core/theme/app_spacing.dart';

// ══════════════════════════════════════════════════════════════════════════════
// BlamedFieldNotice
//
// One sentence, in the place of one field: why the value that was here is gone.
//
// A repair opens the wizard with the field the server refused left empty (see
// NewTicketFormState.fromPendingRow) — an empty required field with no explanation reads as the
// app having lost the technician's work, which is exactly what it must never look like. This is
// the explanation, drawn immediately above the field it belongs to rather than as one banner at
// the top of the step: the technician's eye is on the field, and a step can carry more than one
// reference.
//
// A field whose loss costs more than the value itself — where dropping the reference also dropped
// whatever rode on it — adds a second sentence through [detail]. Deliberately optional, and
// deliberately the same alert: the shared sentence is what happened to the reference, the detail
// is what else went with it, and two alerts stacked on one field would read as two problems.
// ══════════════════════════════════════════════════════════════════════════════

/// The one wording every blamed field shows. A constant, not a literal at each site, so the four
/// steps cannot drift into four ways of saying it.
const String kBlamedFieldNotice = 'Il riferimento non è più valido: scegline un altro';

/// Renders [kBlamedFieldNotice] when [field] is the one the server refused, and nothing at all
/// otherwise — so a step can list one of these above every field it owns unconditionally, with no
/// caller-side conditionals, and an ordinary (non-repair) wizard draws none of them.
class BlamedFieldNotice extends StatelessWidget {
  const BlamedFieldNotice({
    super.key,
    required this.field,
    required this.blamedField,
    this.detail,
  });

  /// The request field this notice sits above, spelled as the server names it in the problem body
  /// ("customerId", "agentId", …) — the same vocabulary [TicketCreationQueue.repairableFieldOf]
  /// stores on the row.
  final String field;

  /// The field the row is waiting on, or null when this is not a repair.
  final String? blamedField;

  /// What else this field's loss cost, as a full sentence, for the few sites where re-picking is
  /// not the whole of the repair. Null — the default — for every field where it is.
  final String? detail;

  @override
  Widget build(BuildContext context) {
    if (blamedField != field) return const SizedBox.shrink();
    // One alert, two sentences at most. The shared wording states what happened to the reference;
    // the caller's detail states what went with it. Both are needed before the technician acts, so
    // both belong in the notice they are already reading.
    final message = detail == null || detail!.isEmpty
        ? kBlamedFieldNotice
        : '$kBlamedFieldNotice. $detail';
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.sm),
      child: InlineAlert(message: message, icon: LucideIcons.alertTriangle),
    );
  }
}
