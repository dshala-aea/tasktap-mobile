// dart format width=100
import 'package:flutter/material.dart';

import '../../core/theme/app_palette.dart';
import '../../core/widgets/widgets.dart';
import '../../data/ai/ai_api_client.dart';

/// The Italian provenance label of one draft value, built from where it came from and how sure the
/// server is. State comes first: a value that is ambiguous, in conflict or still waiting for the
/// technician is labelled as such whatever its source.
///
/// A planned or ticket-recorded value is never evidence that work happened, so those are never
/// labelled as reported by the technician.
String? provenanceLabel(AiFactSource source, AiResolutionState state) {
  switch (state) {
    case AiResolutionState.needsConfirmation:
      return switch (source) {
        AiFactSource.planned => 'Pianificato: conferma',
        AiFactSource.ticketRecord => 'Dal ticket: conferma',
        _ => 'Da confermare',
      };
    case AiResolutionState.ambiguous:
      return 'Da chiarire';
    case AiResolutionState.conflict:
      return 'In conflitto';
    case AiResolutionState.operatorConfirmed:
      return 'Confermato';
    case AiResolutionState.unresolved:
      return 'Non verificato';
    case AiResolutionState.resolvedBySystem:
      return switch (source) {
        AiFactSource.ticketRecord => 'Dal ticket',
        AiFactSource.planned => 'Pianificato',
        AiFactSource.operatorInput => 'Riferito',
        AiFactSource.taskTapTool || AiFactSource.derived => 'Verificato da TaskTap',
      };
  }
}

/// True for a value that came from the ticket or a plan and the technician has not confirmed yet:
/// it must be rendered muted and never presented as done work.
bool isUnconfirmedProposal(AiResolutionState state) =>
    state == AiResolutionState.needsConfirmation;

/// A small badge naming where a draft value came from.
class DraftProvenanceBadge extends StatelessWidget {
  const DraftProvenanceBadge({super.key, required this.source, required this.state});

  final AiFactSource source;
  final AiResolutionState state;

  @override
  Widget build(BuildContext context) {
    final label = provenanceLabel(source, state) ?? '';
    final Color bg;
    final Color fg;
    switch (state) {
      case AiResolutionState.needsConfirmation:
        bg = context.colors.bg3;
        fg = context.colors.inkMuted;
      case AiResolutionState.ambiguous:
        bg = context.colors.amber.withAlpha(31);
        fg = context.colors.amber;
      case AiResolutionState.conflict:
        bg = context.colors.red.withAlpha(31);
        fg = context.colors.red;
      case AiResolutionState.operatorConfirmed:
        bg = context.colors.green.withAlpha(31);
        fg = context.colors.green;
      case AiResolutionState.unresolved:
        bg = context.colors.bg3;
        fg = context.colors.inkMuted;
      case AiResolutionState.resolvedBySystem:
        bg = context.colors.green.withAlpha(31);
        fg = context.colors.green;
    }
    // A planned/unconfirmed badge is outlined (a "stamp", not a filled "done" pill).
    return AppBadge(
      label: label,
      small: true,
      bgColor: bg,
      fgColor: fg,
      outlined: isUnconfirmedProposal(state),
    );
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
