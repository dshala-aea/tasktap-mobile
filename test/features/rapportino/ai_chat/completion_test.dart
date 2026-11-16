// dart format width=100
import 'package:flutter_test/flutter_test.dart';
import 'package:tasktap_mobile/data/ai/ai_api_client.dart';
import 'package:tasktap_mobile/features/rapportino/ai_chat/completion.dart';

AiDraftWorkerRef _worker() => const AiDraftWorkerRef(
  userId: 'u1',
  fullName: 'Mario',
  state: AiResolutionState.resolvedBySystem,
  hours: 2,
);

void main() {
  test('required rules: tecnici and materiali decide readiness', () {
    final empty = AiChatCompletion.fromDraft(AiCopilotDraftDto.empty);
    expect(empty.readyForReview, isFalse);
    expect(empty.missingLabels, ['tecnici', 'materiali']);

    final withFlag = AiChatCompletion.fromDraft(
      AiCopilotDraftDto.empty.copyWith(materialiNotRequired: true),
    );
    expect(
      withFlag.items.firstWhere((i) => i.key == 'materiali').state,
      CompletionState.complete,
    );
    expect(withFlag.readyForReview, isFalse, reason: 'tecnici is still missing');

    final ready = AiChatCompletion.fromDraft(
      AiCopilotDraftDto.empty.copyWith(materialiNotRequired: true, workers: [_worker()]),
    );
    expect(ready.readyForReview, isTrue);
    expect(ready.missingLabels, isEmpty);
  });

  test('controlli is notApplicable when the ticket has none', () {
    final c = AiChatCompletion.fromDraft(AiCopilotDraftDto.empty);
    expect(
      c.items.firstWhere((i) => i.key == 'controlli').state,
      CompletionState.notApplicable,
    );
  });

  test('descrizione is satisfied by activities or diagnosi/soluzione', () {
    final byDiagnosi = AiChatCompletion.fromDraft(
      AiCopilotDraftDto.empty.copyWith(diagnosi: 'Valvola bloccata'),
    );
    expect(
      byDiagnosi.items.firstWhere((i) => i.key == 'descrizione').state,
      CompletionState.complete,
    );

    final bySoluzione = AiChatCompletion.fromDraft(
      AiCopilotDraftDto.empty.copyWith(soluzione: 'Valvola sostituita'),
    );
    expect(
      bySoluzione.items.firstWhere((i) => i.key == 'descrizione').state,
      CompletionState.complete,
    );

    // Blank text is not a description.
    final blank = AiChatCompletion.fromDraft(AiCopilotDraftDto.empty.copyWith(diagnosi: '   '));
    expect(
      blank.items.firstWhere((i) => i.key == 'descrizione').state,
      CompletionState.missing,
    );
  });

  test('a missing description never blocks readiness', () {
    final c = AiChatCompletion.fromDraft(
      AiCopilotDraftDto.empty.copyWith(materialiNotRequired: true, workers: [_worker()]),
    );
    expect(c.items.firstWhere((i) => i.key == 'descrizione').state, CompletionState.missing);
    expect(c.missingLabels, isEmpty);
    expect(c.readyForReview, isTrue);
  });
}
