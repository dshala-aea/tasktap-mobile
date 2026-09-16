import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tasktap_mobile/core/widgets/status_pill.dart';

Widget _wrap(Widget child) => MaterialApp(home: Scaffold(body: child));

void main() {
  const allStati = [
    'Aperto',
    'In corso',
    'In pausa',
    'In attesa',
    'Completato',
    'Chiuso',
    'Annullato',
    'Bozza',
    'Inviata',
    'Pagata',
    'Scaduta',
    'Sospeso',
    'Attivo',
  ];

  // StatusPill now renders through StatusStamp (Il Documento's all-caps stamp device, not a
  // flat pill — see status_pill.dart's own doc comment), which uppercases its label per
  // frontend DESIGN.md's "all-caps ... Archivo Narrow" stamp spec. Assertions below match that
  // deliberate rendering, not the retired pill's original-case text.
  group('StatusPill — all 13 stati', () {
    for (final stato in allStati) {
      testWidgets('renders $stato without error', (tester) async {
        await tester.pumpWidget(_wrap(StatusPill(stato: stato)));
        await tester.pump();
        expect(find.text(stato.toUpperCase()), findsOneWidget);
        expect(tester.takeException(), isNull);
      });
    }
  });

  group('StatusPill — small variant', () {
    for (final stato in allStati) {
      testWidgets('small=true renders $stato', (tester) async {
        await tester.pumpWidget(_wrap(StatusPill(stato: stato, small: true)));
        await tester.pump();
        expect(find.text(stato.toUpperCase()), findsOneWidget);
      });
    }
  });

  testWidgets('StatusPill unknown stato falls back gracefully', (tester) async {
    await tester.pumpWidget(_wrap(const StatusPill(stato: 'Sconosciuto')));
    await tester.pump();
    expect(find.text('SCONOSCIUTO'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
