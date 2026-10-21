// dart format width=100
import 'package:flutter/material.dart';

import '../../core/theme/app_palette.dart';
import '../../core/widgets/widgets.dart';
import '../../data/ai/ai_api_client.dart';

/// The Italian provenance label of one draft value, built from where it came from and how sure the
/// server is. State comes first for the states that need the technician (ambiguous, conflict,
/// needs-confirmation); after that any value whose source is the technician is `Riferito`
/// (reported or recorded: dictated, typed or hand-edited), whatever its exact state.
///
/// A planned or ticket-recorded value is never evidence that work happened, so those are never
/// labelled as reported by the technician (unless the technician confirmed it).
String? provenanceLabel(AiFactSource source, AiResolutionState state) {
  switch (state) {
    case AiResolutionState.ambiguous:
      return 'Da chiarire';
    case AiResolutionState.conflict:
      return 'In conflitto';
    case AiResolutionState.operatorConfirmed:
      return 'Riferito';
    case AiResolutionState.needsConfirmation:
    case AiResolutionState.resolvedBySystem:
    case AiResolutionState.unresolved:
      break;
  }
  switch (source) {
    case AiFactSource.operatorInput:
      return state == AiResolutionState.needsConfirmation ? 'Da confermare' : 'Riferito';
    case AiFactSource.planned:
      return 'Pianificato: conferma';
    case AiFactSource.ticketRecord:
      return state == AiResolutionState.resolvedBySystem ? 'Dal ticket' : 'Dal ticket: conferma';
    case AiFactSource.taskTapTool:
    case AiFactSource.derived:
      return state == AiResolutionState.resolvedBySystem ? 'Verificato da TaskTap' : 'Non verificato';
  }
}

/// True for a value that came from the ticket or a plan (or is waiting for confirmation) and the
/// technician has not confirmed: it must be rendered muted and never presented as done work. Any
/// state counts, so an unknown future state on a planned value is muted too.
bool isUnconfirmedProposal(AiFactSource source, AiResolutionState state) {
  if (state == AiResolutionState.ambiguous ||
      state == AiResolutionState.conflict ||
      state == AiResolutionState.operatorConfirmed) {
    return false;
  }
  if (state == AiResolutionState.needsConfirmation) return true;
  return source == AiFactSource.planned || source == AiFactSource.ticketRecord;
}

/// A small badge naming where a draft value came from.
class DraftProvenanceBadge extends StatelessWidget {
  const DraftProvenanceBadge({super.key, required this.source, required this.state});

  final AiFactSource source;
  final AiResolutionState state;

  @override
  Widget build(BuildContext context) {
    final label = provenanceLabel(source, state) ?? '';
    final unconfirmed = isUnconfirmedProposal(source, state);
    final Color bg;
    final Color fg;
    if (unconfirmed) {
      bg = context.colors.bg3;
      fg = context.colors.inkMuted;
    } else {
      switch (state) {
        case AiResolutionState.ambiguous:
          bg = context.colors.amber.withAlpha(31);
          fg = context.colors.amber;
        case AiResolutionState.conflict:
          bg = context.colors.red.withAlpha(31);
          fg = context.colors.red;
        case AiResolutionState.unresolved:
          bg = context.colors.bg3;
          fg = context.colors.inkMuted;
        case AiResolutionState.operatorConfirmed:
        case AiResolutionState.resolvedBySystem:
        case AiResolutionState.needsConfirmation:
          bg = context.colors.green.withAlpha(31);
          fg = context.colors.green;
      }
    }
    // An unconfirmed badge is outlined (a "stamp", not a filled "done" pill).
    return AppBadge(label: label, small: true, bgColor: bg, fgColor: fg, outlined: unconfirmed);
  }
}

/// A one-line Italian description of an open item the technician has to resolve.
String describeOpenItem(AiCandidateFact item) {
  if (item.isHeldRemoval) {
    final what = switch (item.removedCollection) {
      'workers' => 'il tecnico',
      'materials' => 'il materiale',
      'activities' => 'l\'attività',
      'controlli' => 'la risposta della checklist',
      _ => 'una voce',
    };
    final name = item.conflictOperatorValue;
    final named = (name == null || name.isEmpty) ? what : '$what «$name»';
    return 'Hai rimosso $named ma è stato riproposto: resta fuori finché non lo '
        'confermi o lo reinserisci a mano.';
  }
  final kind = switch (item.state) {
    AiResolutionState.conflict => 'In conflitto',
    AiResolutionState.ambiguous => 'Da chiarire',
    _ => 'Da verificare',
  };
  return '$kind: ${item.field}';
}
