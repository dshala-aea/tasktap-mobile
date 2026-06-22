import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tasktap_mobile/presentation/screens/placeholder/altro_screen.dart';
import 'package:tasktap_mobile/presentation/screens/placeholder/calendario_placeholder_screen.dart';

void main() {
  testWidgets('CalendarioPlaceholderScreen renders without error',
      (tester) async {
    await tester.pumpWidget(
      const MaterialApp(home: CalendarioPlaceholderScreen()),
    );
    expect(find.byType(Scaffold), findsOneWidget);
    expect(find.text('Calendario'), findsOneWidget);
  });

  testWidgets('AltroScreen renders without error', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(home: AltroScreen()),
    );
    expect(find.byType(Scaffold), findsOneWidget);
    expect(find.text('Altro'), findsOneWidget);
    expect(find.text('Rapportini'), findsOneWidget);
    expect(find.text('Profilo'), findsOneWidget);
  });
}
