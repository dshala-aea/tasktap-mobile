// test/features/rapportino/ai_assisted_badge_test.dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tasktap_mobile/features/rapportino/ai_assisted_badge.dart';

void main() {
  testWidgets('renders the AI badge with its accessible name', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(home: Scaffold(body: AiAssistedBadge())),
    );

    expect(find.text('AI'), findsOneWidget);
    expect(
      find.byWidgetPredicate(
        (w) => w is Semantics && w.properties.label == 'Assistito da AI',
      ),
      findsOneWidget,
    );
  });
}
