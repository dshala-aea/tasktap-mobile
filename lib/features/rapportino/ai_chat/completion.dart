// dart format width=100
import '../../../data/ai/ai_api_client.dart';

/// How one item of the chat's status strip reads.
enum CompletionState {
  /// Present, and the server's send gate is satisfied by it.
  complete,

  /// The send gate needs it and it is not there.
  missing,

  /// Nothing to satisfy: the ticket has no checklist, so the item cannot be "missing".
  notApplicable,
}

/// One named item ("tecnici", "materiali", "controlli", "descrizione").
class CompletionItem {
  const CompletionItem(this.key, this.state);

  final String key;
  final CompletionState state;
}

/// What the status strip shows, derived from the same draft the server returns after every turn.
///
/// The strip is an indicator, not a guard: the authoritative gate is `ReportStateMachine.CanInvia`
/// on the server. `readyForReview` mirrors only what the gate demands beyond the signatures — a
/// technician and a material (or the "nessun materiale" flag).
class AiChatCompletion {
  const AiChatCompletion({
    required this.items,
    required this.readyForReview,
    required this.missingLabels,
  });

  final List<CompletionItem> items;
  final bool readyForReview;

  /// Keys whose state is [CompletionState.missing], in strip order. Only the items the SEND GATE
  /// requires; a missing description is shown as a chip but does not appear here.
  final List<String> missingLabels;

  static AiChatCompletion fromDraft(AiCopilotDraftDto draft) {
    final hasNarrative =
        draft.activities.isNotEmpty || _nonEmpty(draft.diagnosi) || _nonEmpty(draft.soluzione);

    final tecnici = draft.workers.isNotEmpty ? CompletionState.complete : CompletionState.missing;
    final materiali = draft.materials.isNotEmpty || draft.materialiNotRequired
        ? CompletionState.complete
        : CompletionState.missing;
    final controlli = draft.controlli.isEmpty
        ? CompletionState.notApplicable
        : CompletionState.complete;
    final descrizione = hasNarrative ? CompletionState.complete : CompletionState.missing;

    final items = [
      CompletionItem('tecnici', tecnici),
      CompletionItem('materiali', materiali),
      CompletionItem('controlli', controlli),
      CompletionItem('descrizione', descrizione),
    ];
    final missing = [
      if (tecnici == CompletionState.missing) 'tecnici',
      if (materiali == CompletionState.missing) 'materiali',
    ];

    return AiChatCompletion(
      items: items,
      readyForReview: missing.isEmpty,
      missingLabels: missing,
    );
  }

  static bool _nonEmpty(String? s) => s != null && s.trim().isNotEmpty;
}
