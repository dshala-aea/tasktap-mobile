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
  testWidgets('summary says ready when required items are complete', (tester) async {
    await _pump(
      tester,
      AiChatCompletion.fromDraft(
        AiCopilotDraftDto.empty.copyWith(materialiNotRequired: true, workers: [_worker()]),
      ),
    );

    expect(find.byKey(const ValueKey('ai-completion-summary')), findsOneWidget);
    expect(find.text('Pronto per la revisione'), findsOneWidget);
  });

  testWidgets('summary names what is missing', (tester) async {
    await _pump(tester, AiChatCompletion.fromDraft(AiCopilotDraftDto.empty));

    expect(find.text('Manca: tecnici, materiali'), findsOneWidget);
  });

  testWidgets('controlli reads as not applicable when the ticket has none', (tester) async {
    await _pump(tester, AiChatCompletion.fromDraft(AiCopilotDraftDto.empty));

    expect(find.byKey(const ValueKey('ai-completion-controlli')), findsOneWidget);
    expect(find.text('Controlli · se previsti'), findsOneWidget);
    expect(find.text('Manca: tecnici, materiali'), findsOneWidget);
  });

  testWidgets('the materiali chip is complete when the no-materials flag is set', (tester) async {
    await _pump(
      tester,
      AiChatCompletion.fromDraft(AiCopilotDraftDto.empty.copyWith(materialiNotRequired: true)),
    );

    expect(find.text('Manca: tecnici'), findsOneWidget);
    expect(find.text('Manca: tecnici, materiali'), findsNothing);
  });
}
