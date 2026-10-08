// dart format width=100
import 'package:flutter/material.dart';

import 'package:tasktap_mobile/core/theme/app_palette.dart';
import 'package:tasktap_mobile/core/theme/app_spacing.dart';

// ══════════════════════════════════════════════════════════════════════════════
// ReadOnlyFieldCaption
//
// One sentence under a field this screen deliberately does not offer for editing.
//
// Edit mode reuses the create wizard's two steps, and both of them draw references the PUT behind
// this screen cannot write: a contract (no `ContractId` on `UpdateTicketRequest`), a commessa clear
// (applied set-only server-side) and the coverage list (replaced wholesale, with no authoritative
// local copy to replace it from). Removing the controls would leave the technician wondering where
// their contract went; leaving them silently live would let a pick be discarded without a word.
// This is the third option — and what stands above it differs by site, because the sites do:
//
//  - under the Contratto picker it is a real field. Edit mode seeds the record's own contract, so
//    the field is drawn disabled showing the contract the ticket actually holds, and the caption
//    says why it is not a control here;
//  - under the Prodotti assistenza list it stands alone. Edit mode seeds no coverage at all
//    (deliberately — see `StepDettagliTicket.prodottiEditable`), so no chip and no adder is drawn
//    there either, and this sentence is the whole of what the section says.
//
// The commessa is the third reference edit mode will not move, and it carries no caption: its field
// stays enabled because a pick there is real, so "not modifiable here" would be untrue of it. Its
// one refused gesture says so itself, with a toast.
//
// A constant, not a literal at each site, for the same reason [kBlamedFieldNotice] is one: the two
// steps must not drift into two ways of saying the same thing.
// ══════════════════════════════════════════════════════════════════════════════

/// The one wording every read-only field shows.
const String kReadOnlyFieldCaption = 'Non modificabile in questa schermata.';

/// Draws [kReadOnlyFieldCaption]. Callers put it under the field it explains, unconditionally —
/// the decision to explain was already made at the call site by the flag that disabled the field.
class ReadOnlyFieldCaption extends StatelessWidget {
  const ReadOnlyFieldCaption({super.key});

  @override
  Widget build(BuildContext context) {
    return Padding(
      // Same shape as the other caption this form draws under a field — `ReferencePickerField`'s
      // "Non in linea" line and `AppLookupField`'s empty-cache hint — so a caption reads as one
      // kind of thing wherever it appears.
      padding: const EdgeInsets.only(top: 6, left: AppSpacing.xs),
      child: Text(
        kReadOnlyFieldCaption,
        style: TextStyle(fontSize: 12, color: context.colors.inkMuted),
      ),
    );
  }
}
