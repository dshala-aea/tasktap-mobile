import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
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
}
