// dart format width=100
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tasktap_mobile/features/rapportino/existing_draft_prompt.dart';

/// Pumps a screen that opens [promptExistingDraft] on its first frame and records the answer.
Widget _host(void Function(ExistingDraftChoice?) onResult) {
  return MaterialApp(
    home: Builder(
      builder: (context) {
        WidgetsBinding.instance.addPostFrameCallback((_) async {
          final choice = await promptExistingDraft(
            context,
            draftTitle: 'Rapportino — Sostituzione scheda',
            lastTouchedAt: DateTime.utc(2026, 6, 21, 10, 30),
          );
          onResult(choice);
        });
        return const Scaffold(body: SizedBox());
      },
    ),
  );
}

void main() {
  testWidgets('names the draft it would resume', (tester) async {
    await tester.pumpWidget(_host((_) {}));
    await tester.pumpAndSettle();

    expect(find.text('Bozza già presente'), findsOneWidget);
    expect(find.textContaining('Rapportino — Sostituzione scheda'), findsOneWidget);
  });

  testWidgets('resume is the answer when the technician resumes', (tester) async {
    ExistingDraftChoice? result;
    var answered = false;
    await tester.pumpWidget(
      _host((choice) {
        result = choice;
        answered = true;
      }),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Riprendi bozza'));
    await tester.pumpAndSettle();

    expect(answered, isTrue);
    expect(result, ExistingDraftChoice.resume);
  });

  testWidgets('creating a second draft is a separate, deliberate answer', (tester) async {
    ExistingDraftChoice? result;
    var answered = false;
    await tester.pumpWidget(
      _host((choice) {
        result = choice;
        answered = true;
      }),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Crea una nuova bozza'));
    await tester.pumpAndSettle();

    expect(answered, isTrue);
    expect(result, ExistingDraftChoice.createNew);
  });

  testWidgets('dismissing answers nothing, so nothing is created', (tester) async {
    ExistingDraftChoice? result = ExistingDraftChoice.resume;
    var answered = false;
    await tester.pumpWidget(
      _host((choice) {
        result = choice;
        answered = true;
      }),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Annulla'));
    await tester.pumpAndSettle();

    expect(answered, isTrue);
    expect(result, isNull);
  });
}
