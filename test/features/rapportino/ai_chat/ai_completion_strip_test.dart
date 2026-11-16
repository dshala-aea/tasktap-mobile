// dart format width=100
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tasktap_mobile/data/ai/ai_api_client.dart';
import 'package:tasktap_mobile/features/rapportino/ai_chat/ai_completion_strip.dart';
import 'package:tasktap_mobile/features/rapportino/ai_chat/completion.dart';

AiDraftWorkerRef _worker() => const AiDraftWorkerRef(
  userId: 'u1',
  fullName: 'Mario',
  state: AiResolutionState.resolvedBySystem,
  hours: 2,
);

Future<void> _pump(WidgetTester tester, AiChatCompletion completion) => tester.pumpWidget(
  MaterialApp(home: Scaffold(body: AiCompletionStrip(completion: completion))),
);

void main() {
  testWidgets('a complete draft reads as four complete chips, with no summary line', (tester) async {
    await _pump(
      tester,
      AiChatCompletion.fromDraft(
        AiCopilotDraftDto.empty.copyWith(
          materialiNotRequired: true,
          workers: [_worker()],
          diagnosi: 'Valvola bloccata',
        ),
      ),
    );

    for (final key in ['tecnici', 'materiali', 'controlli', 'descrizione']) {
      expect(find.byKey(ValueKey('ai-completion-$key')), findsOneWidget);
    }
    // The chips ARE the summary: the second line that restated them was noise, and it could
    // contradict them ("Pronto per la revisione" over an amber chip).
    expect(find.byKey(const ValueKey('ai-completion-summary')), findsNothing);
    expect(find.textContaining('Pronto per la revisione'), findsNothing);
    expect(find.textContaining('Manca:'), findsNothing);
  });

  testWidgets('missing items are named on their own chips', (tester) async {
    await _pump(tester, AiChatCompletion.fromDraft(AiCopilotDraftDto.empty));

    expect(find.text('Tecnici'), findsOneWidget);
    expect(find.text('Materiali'), findsOneWidget);
    expect(find.text('Descrizione'), findsOneWidget);
  });

  testWidgets('controlli reads as not applicable without a suffix crowding the row', (tester) async {
    await _pump(tester, AiChatCompletion.fromDraft(AiCopilotDraftDto.empty));

    expect(find.byKey(const ValueKey('ai-completion-controlli')), findsOneWidget);
    expect(find.text('Controlli'), findsOneWidget);
    // The "se previsti" caveat moved into the chip's semantic label.
    expect(find.textContaining('se previsti'), findsNothing);
  });

  testWidgets('the materiali chip is complete when the no-materials flag is set', (tester) async {
    final completion = AiChatCompletion.fromDraft(
      AiCopilotDraftDto.empty.copyWith(materialiNotRequired: true),
    );
    await _pump(tester, completion);

    final materiali = completion.items.firstWhere((i) => i.key == 'materiali');
    expect(materiali.state, CompletionState.complete);
    expect(completion.missingLabels, ['tecnici']);
  });
}
