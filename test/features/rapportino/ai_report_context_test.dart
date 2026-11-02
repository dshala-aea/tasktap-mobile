// dart format width=100
// "What this report is about" on the Controlla step.
//
// A technician reporting on a ticket used to open the review screen onto the assistant's own
// output alone — no ticket, no customer, no site — and, when the assistant compiled nothing, onto
// a genuinely blank screen with a Confirm button under it. The card names the intervento; the test
// fixes only what it must: the label and the values, and that a value the mirror does not have is
// absent rather than a placeholder.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:tasktap_mobile/features/rapportino/ai_report/ai_report_context.dart';

Future<void> _pump(WidgetTester tester, AiReportContext context) => tester.pumpWidget(
  MaterialApp(home: Scaffold(body: AiReportContextCard(context: context))),
);

void main() {
  testWidgets('names the intervento, the customer and the site', (tester) async {
    await _pump(
      tester,
      const AiReportContext(ticketLabel: '12 · Guasto caldaia', cliente: 'Rossi Srl', sede: 'Via Roma'),
    );

    // AiLabel upper-cases in build, so the widget tree never holds the mixed-case string.
    expect(find.text('INTERVENTO'), findsOneWidget);
    expect(find.text('12 · Guasto caldaia'), findsOneWidget);
    expect(find.text('Cliente · Rossi Srl · Sede · Via Roma'), findsOneWidget);
  });

  testWidgets('a ticket with no numero shows the title alone', (tester) async {
    await _pump(tester, const AiReportContext(ticketLabel: 'Guasto caldaia'));

    expect(find.text('Guasto caldaia'), findsOneWidget);
  });

  testWidgets('an unresolved customer or site is omitted, never filled with a placeholder', (
    tester,
  ) async {
    // A stale mirror is the ordinary case on a phone that has been offline: the card degrades to
    // what it knows. Printing "Cliente · —" would read as a customer named nothing.
    await _pump(tester, const AiReportContext(ticketLabel: '12 · Guasto caldaia', sede: 'Via Roma'));

    expect(find.text('Sede · Via Roma'), findsOneWidget);
    expect(find.text('INTERVENTO'), findsOneWidget);
    expect(find.textContaining('Cliente'), findsNothing);
    expect(find.textContaining('—'), findsNothing);
  });

  testWidgets('a long ticket title wraps instead of overflowing', (tester) async {
    // AiKvRow's value is a bare Text inside a Row and would clip here; the card uses AiValue.
    await _pump(
      tester,
      const AiReportContext(
        ticketLabel:
            '12 · Sostituzione della valvola di sicurezza del gruppo termico principale, piano interrato',
        cliente: 'Consorzio Edifici Storici del Centro',
        sede: 'Palazzo Vecchio, scala B, piano interrato, locale caldaia',
      ),
    );

    expect(tester.takeException(), isNull);
  });
}
