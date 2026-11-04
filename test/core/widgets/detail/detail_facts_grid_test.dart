import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tasktap_mobile/core/widgets/detail/detail_facts_grid.dart';
import 'package:tasktap_mobile/core/widgets/detail/detail_hero.dart';

void main() {
  Widget host(Widget child, {double width = 320}) => MaterialApp(
    home: Scaffold(
      body: Center(
        child: SizedBox(width: width, child: child),
      ),
    ),
  );

  testWidgets('lays facts out two per row with uppercase mono labels', (
    tester,
  ) async {
    await tester.pumpWidget(
      host(
        const DetailFactsGrid(
          facts: [
            DetailFact(label: 'Cliente', value: 'Rossi Srl'),
            DetailFact(label: 'Sede', value: 'Milano'),
            DetailFact(label: 'Tecnico', value: 'Daniel Shala'),
            DetailFact(label: 'Commessa', value: 'CM-2026-018'),
          ],
        ),
      ),
    );

    expect(find.text('CLIENTE'), findsOneWidget);
    expect(find.text('Rossi Srl'), findsOneWidget);
    final cliente = tester.getTopLeft(find.text('Rossi Srl'));
    final sede = tester.getTopLeft(find.text('Milano'));
    final tecnico = tester.getTopLeft(find.text('Daniel Shala'));
    expect(sede.dy, cliente.dy, reason: 'first row shares a baseline');
    expect(sede.dx, greaterThan(cliente.dx));
    expect(tecnico.dy, greaterThan(cliente.dy));
    expect(tecnico.dx, cliente.dx);

    final label = tester.widget<Text>(find.text('CLIENTE'));
    expect(label.style!.fontFamily, 'IBM Plex Mono');
    expect(label.style!.fontSize, 8);
    final value = tester.widget<Text>(find.text('Rossi Srl'));
    expect(value.style!.fontSize, 11.5);
    expect(value.maxLines, 1);
    expect(value.overflow, TextOverflow.ellipsis);
  });

  testWidgets('an odd count leaves the last cell empty and does not throw', (
    tester,
  ) async {
    await tester.pumpWidget(
      host(
        const DetailFactsGrid(
          facts: [
            DetailFact(label: 'A', value: '1'),
            DetailFact(label: 'B', value: '2'),
            DetailFact(label: 'C', value: '3'),
          ],
        ),
      ),
    );
    expect(tester.takeException(), isNull);
    expect(find.text('3'), findsOneWidget);
  });

  testWidgets('long values ellipsize on one line at 320px', (tester) async {
    await tester.pumpWidget(
      host(
        const DetailFactsGrid(
          facts: [
            DetailFact(
              label: 'Tecnico',
              value:
                  'Giovanni Battista Alessandro Michelangelo Della Valle di Torrente Montanari',
            ),
            DetailFact(label: 'Sede', value: 'Milano'),
          ],
        ),
      ),
    );
    expect(tester.takeException(), isNull);
    expect(
      tester.getSize(find.textContaining('Giovanni')).height,
      lessThan(20),
    );
  });

  testWidgets('a fact with onTap is tappable', (tester) async {
    var taps = 0;
    await tester.pumpWidget(
      host(
        DetailFactsGrid(
          facts: [
            DetailFact(
              label: 'Cliente',
              value: 'Rossi Srl',
              onTap: () => taps++,
            ),
            const DetailFact(label: 'Sede', value: 'Milano'),
          ],
        ),
      ),
    );
    await tester.tap(find.text('Rossi Srl'));
    expect(taps, 1);
  });

  testWidgets('empty facts render nothing', (tester) async {
    await tester.pumpWidget(host(const DetailFactsGrid(facts: [])));
    expect(find.byKey(const Key('detail-facts-grid')), findsNothing);
  });
}
