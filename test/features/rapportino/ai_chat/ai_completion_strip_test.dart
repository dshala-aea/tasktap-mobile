// dart format width=100
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tasktap_mobile/core/theme/app_palette.dart';
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

Color? _segment(WidgetTester tester, String key) {
  final container = tester.widget<Container>(find.byKey(ValueKey('ai-completion-$key')));
  return (container.decoration! as BoxDecoration).color;
}

void main() {
  final colors = AppPalette.light;

  testWidgets('a fully captured draft drops the rail and keeps the line', (tester) async {
    await _pump(
      tester,
      AiChatCompletion.fromDraft(
        AiCopilotDraftDto.empty.copyWith(
          materialiNotRequired: true,
          workers: [_worker()],
          diagnosi: 'Valvola bloccata',
          controlli: [
            const AiDraftControlAnswer(
              ticketControlId: 'tc-1',
              boolValue: true,
              state: AiResolutionState.resolvedBySystem,
            ),
          ],
        ),
      ),
    );

    // Four green segments say nothing the caption has not said.
    expect(find.byKey(const ValueKey('ai-completion-rail')), findsNothing);
    expect(find.text('Pronto per la revisione'), findsOneWidget);
  });

  testWidgets('a missing required item fills amber and the caption names it', (tester) async {
    await _pump(tester, AiChatCompletion.fromDraft(AiCopilotDraftDto.empty));

    expect(_segment(tester, 'tecnici'), colors.amber);
    expect(_segment(tester, 'materiali'), colors.amber);
    // Nothing to satisfy: a slot, not a red flag.
    expect(_segment(tester, 'controlli'), colors.bg3);
    expect(find.text('Manca: tecnici, materiali'), findsOneWidget);
  });

  testWidgets('a soft gap never contradicts the ready caption', (tester) async {
    // The old summary line could read "Pronto per la revisione" over an amber Descrizione chip,
    // because the line came from one list and the chips from another. Rail and caption are now the
    // same list: a description the gate does not require is a slot, and the caption stays honest.
    final completion = AiChatCompletion.fromDraft(
      AiCopilotDraftDto.empty.copyWith(materialiNotRequired: true, workers: [_worker()]),
    );
    await _pump(tester, completion);

    expect(completion.readyForReview, isTrue);
    expect(_segment(tester, 'descrizione'), colors.bg3);
    expect(find.text('Pronto per la revisione'), findsOneWidget);
    expect(find.textContaining('Manca:'), findsNothing);
  });

  testWidgets('the no-materials flag fills materiali', (tester) async {
    final completion = AiChatCompletion.fromDraft(
      AiCopilotDraftDto.empty.copyWith(materialiNotRequired: true),
    );
    await _pump(tester, completion);

    expect(_segment(tester, 'materiali'), colors.green);
    expect(completion.missingLabels, ['tecnici']);
    expect(find.text('Manca: tecnici'), findsOneWidget);
  });
}
