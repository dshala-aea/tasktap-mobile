// dart format width=100
import 'package:flutter/material.dart';

import '../../../core/theme/app_palette.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../data/ai/ai_api_client.dart';
import '../ai_draft_feed.dart';
import '../draft_provenance_badge.dart';
import 'ai_card.dart';

// ══════════════════════════════════════════════════════════════════════════════
// Step 2 of the AI report flow: "Controlla" — what the assistant compiled, as cards.
//
// Read-only by design in this slice. Every value the assistant could not derive is drawn as a
// dashed "Da completare" card rather than as a blank field, so an unconfirmed value never reads as
// work that was done (same rule `isUnconfirmedProposal` encodes for the badges). The technician
// changes the content by describing it again on step 1, or — once Confirm has created the local
// draft — in the ordinary report editor, which the Firma screen links to. Inline editing of these
// cards is the one part of the design pack not built yet.
// ══════════════════════════════════════════════════════════════════════════════

class AiReviewStep extends StatelessWidget {
  const AiReviewStep({
    super.key,
    required this.draft,
    required this.busy,
    required this.onAccept,
    required this.onResolveHeld,
  });

  final AiCopilotDraftDto draft;

  /// A turn or an edit is in flight: the accept actions are disabled, never removed.
  final bool busy;

  final void Function(AiConfirmedEdit) onAccept;
  final void Function(AiCandidateFact item, {required bool reAdd}) onResolveHeld;

  /// Italian decimal comma, integer when the value is whole.
  ///
  /// Ore already obeyed this rule while Materiali printed the raw `double`, so the same screen
  /// read `1.5 pz` beside `1,5 h`. One screen, one number convention; the caller appends the unit.
  static String _number(double v) =>
      v == v.roundToDouble() ? v.round().toString() : v.toString().replaceAll('.', ',');

  static String _hours(double h) => '${_number(h)} h';

  @override
  Widget build(BuildContext context) {
    final activityText = draft.activities
        .map((a) => a.description.trim())
        .where((d) => d.isNotEmpty)
        .join(' ');
    final hours = draft.workers
        .map((w) => w.hours)
        .whereType<double>()
        .fold<double>(0, (a, b) => a + b);
    final note = draft.customerSignoffText?.trim();

    return ListView(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.pagePadding,
        AppSpacing.base,
        AppSpacing.pagePadding,
        AppSpacing.base,
      ),
      children: [
        const AiProvenanceBand(),
        const AiCardGap(dense: true),

        // ── Lavoro svolto ─────────────────────────────────────────────────────
        if (activityText.isEmpty)
          AiCard(
            todo: true,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: const [
                AiLabel('Lavoro svolto'),
                SizedBox(height: 4),
                AiHelper('Da completare'),
              ],
            ),
          )
        else
          AiCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const AiLabel('Lavoro svolto'),
                const SizedBox(height: 4),
                AiValue(activityText, muted: draft.activities.every((a) => isUnconfirmedProposal(a.source, a.state))),
                if (draft.activities.any((a) => a.hours != null))
                  Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: AiHelper(
                      draft.activities
                          .where((a) => a.hours != null)
                          .map((a) => '${a.description.isEmpty ? '—' : a.description} · ${_hours(a.hours!)}')
                          .join(' · '),
                    ),
                  ),
              ],
            ),
          ),
        const AiCardGap(dense: true),

        // ── Materiali ─────────────────────────────────────────────────────────
        AiCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const AiLabel('Materiali'),
              if (draft.materials.isEmpty)
                const Padding(
                  padding: EdgeInsets.only(top: 4),
                  child: AiHelper('Nessun materiale indicato'),
                )
              else
                for (var i = 0; i < draft.materials.length; i++)
                  _materialRow(context, draft.materials[i], first: i == 0),
            ],
          ),
        ),
        const AiCardGap(dense: true),

        // ── Ore ───────────────────────────────────────────────────────────────
        if (hours > 0)
          AiCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const AiLabel('Ore'),
                const SizedBox(height: 2),
                Text(
                  _hours(hours),
                  style: TextStyle(
                    fontFamily: 'Archivo Narrow',
                    fontSize: 22,
                    fontWeight: FontWeight.w700,
                    color: context.colors.ink,
                  ),
                ),
              ],
            ),
          )
        else
          AiCard(
            todo: true,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: const [
                AiLabel('Ore'),
                SizedBox(height: 4),
                AiHelper('Da completare'),
              ],
            ),
          ),
        const AiCardGap(dense: true),

        // ── Note per il cliente ───────────────────────────────────────────────
        if (note != null && note.isNotEmpty) ...[
          AiCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const AiLabel('Note per il cliente'),
                const SizedBox(height: 4),
                AiValue(note),
              ],
            ),
          ),
          const AiCardGap(dense: true),
        ],

        // ── Controlli eseguiti ────────────────────────────────────────────────
        if (draft.controlli.isNotEmpty) ...[
          AiCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const AiLabel('Controlli eseguiti'),
                for (var i = 0; i < draft.controlli.length; i++)
                  AiKvRow(
                    first: i == 0,
                    label: draft.controlli[i].describe(),
                    value: draft.controlli[i].state == AiResolutionState.needsConfirmation
                        ? 'da confermare'
                        : 'eseguito',
                  ),
              ],
            ),
          ),
          const AiCardGap(dense: true),
        ],

        // ── Strumenti ─────────────────────────────────────────────────────────
        if (draft.strumenti.isNotEmpty) ...[
          AiCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const AiLabel('Strumenti'),
                for (var i = 0; i < draft.strumenti.length; i++)
                  AiKvRow(
                    first: i == 0,
                    label: draft.strumenti[i].name,
                    value: draft.strumenti[i].matricola ?? '',
                    // A name with no catalogue id is a line the technician still has to pick —
                    // shown as such, never as a chosen instrument.
                    note: draft.strumenti[i].strumentoId.isEmpty
                        ? "Da scegliere dall'anagrafico"
                        : null,
                    noteIsError: draft.strumenti[i].strumentoId.isEmpty,
                  ),
              ],
            ),
          ),
          const AiCardGap(dense: true),
        ],

        // ── Punti da chiarire ─────────────────────────────────────────────────
        if (draft.openItems.isNotEmpty) ...[
          AiCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                AiLabel(
                  draft.hasBlockingOpenItems
                      ? 'Da chiarire prima di confermare'
                      : 'Da chiarire',
                  color: draft.hasBlockingOpenItems ? context.colors.red : null,
                ),
                for (final item in draft.openItems) ...[
                  Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: Text(
                      describeOpenItem(item),
                      style: TextStyle(
                        fontFamily: 'Archivo',
                        fontSize: 13,
                        height: 1.35,
                        color: item.state == AiResolutionState.conflict
                            ? context.colors.red
                            : context.colors.ink,
                      ),
                    ),
                  ),
                  if (item.isHeldRemoval)
                    Row(
                      children: [
                        if (AiEditSyncer.heldRemovalEdit(item, reAdd: true) != null)
                          TextButton(
                            onPressed: busy
                                ? null
                                : () => onResolveHeld(item, reAdd: true),
                            style: TextButton.styleFrom(minimumSize: const Size(44, 44)),
                            child: const Text('Reinserisci'),
                          ),
                        if (AiEditSyncer.heldRemovalEdit(item, reAdd: false) != null)
                          TextButton(
                            onPressed: busy
                                ? null
                                : () => onResolveHeld(item, reAdd: false),
                            style: TextButton.styleFrom(minimumSize: const Size(44, 44)),
                            child: const Text('Mantieni rimosso'),
                          ),
                      ],
                    ),
                ],
              ],
            ),
          ),
        ],
      ],
    );
  }

  Widget _materialRow(BuildContext context, AiDraftMaterialUsage m, {required bool first}) {
    final unconfirmed = isUnconfirmedProposal(m.source, m.state);
    final unit = (m.unit ?? '').trim();
    final accept = m.state == AiResolutionState.needsConfirmation
        ? AiEditSyncer.acceptMaterial(m)
        : null;
    return AiKvRow(
      first: first,
      label: m.name.isEmpty ? '—' : m.name,
      value: '${_number(m.quantity)}${unit.isEmpty ? '' : ' $unit'}',
      note: m.isFreeText || m.materialId.isEmpty ? "Non in anagrafica · scegli l'articolo" : null,
      noteIsError: m.isFreeText || m.materialId.isEmpty,
      trailing: accept != null
          ? TextButton(
              onPressed: busy ? null : () => onAccept(accept),
              style: TextButton.styleFrom(minimumSize: const Size(44, 44)),
              child: const Text('Accetta'),
            )
          : (unconfirmed
                ? DraftProvenanceBadge(source: m.source, state: m.state)
                : null),
    );
  }
}
