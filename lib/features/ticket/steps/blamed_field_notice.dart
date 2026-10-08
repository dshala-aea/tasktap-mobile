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
// ══════════════════════════════════════════════════════════════════════════════

/// The one wording every blamed field shows. A constant, not a literal at each site, so the four
/// steps cannot drift into four ways of saying it.
const String kBlamedFieldNotice = 'Il riferimento non è più valido: scegline un altro';

/// Renders [kBlamedFieldNotice] when [field] is the one the server refused, and nothing at all
/// otherwise — so a step can list one of these above every field it owns unconditionally, with no
/// caller-side conditionals, and an ordinary (non-repair) wizard draws none of them.
class BlamedFieldNotice extends StatelessWidget {
  const BlamedFieldNotice({super.key, required this.field, required this.blamedField});

  /// The request field this notice sits above, spelled as the server names it in the problem body
  /// ("customerId", "agentId", …) — the same vocabulary [TicketCreationQueue.repairableFieldOf]
  /// stores on the row.
  final String field;

  /// The field the row is waiting on, or null when this is not a repair.
  final String? blamedField;

  @override
  Widget build(BuildContext context) {
    if (blamedField != field) return const SizedBox.shrink();
    return const Padding(
      padding: EdgeInsets.only(bottom: AppSpacing.sm),
      child: InlineAlert(message: kBlamedFieldNotice, icon: LucideIcons.alertTriangle),
    );
  }
}
