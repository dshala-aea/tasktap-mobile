import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tasktap_mobile/core/widgets/unavailable_state.dart';

void main() {
  testWidgets('states the reason, not just that something is missing', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: UnavailableState(
            titolo: 'Matricole non disponibili',
            motivo: 'Il catalogo prodotti gestisce una sola matricola per prodotto.',
          ),
        ),
      ),
    );

    expect(find.text('Matricole non disponibili'), findsOneWidget);
    expect(
      find.text('Il catalogo prodotti gestisce una sola matricola per prodotto.'),
      findsOneWidget,
    );
  });
}
