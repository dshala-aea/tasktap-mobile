import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tasktap_mobile/main.dart';

void main() {
  group('TaskTapApp shell smoke test', () {
    testWidgets('app renders without throwing', (tester) async {
      await tester.pumpWidget(
        const ProviderScope(
          child: TaskTapApp(),
        ),
      );
      await tester.pumpAndSettle(const Duration(seconds: 2));

      // The shell should be on screen (no exception thrown).
      expect(find.byType(MaterialApp), findsWidgets);
    });

    testWidgets('bottom navigation bar is visible', (tester) async {
      await tester.pumpWidget(
        const ProviderScope(
          child: TaskTapApp(),
        ),
      );
      await tester.pumpAndSettle(const Duration(seconds: 2));

      expect(find.byType(NavigationBar), findsOneWidget);
    });

    testWidgets('bottom nav has 4 destinations', (tester) async {
      await tester.pumpWidget(
        const ProviderScope(
          child: TaskTapApp(),
        ),
      );
      await tester.pumpAndSettle(const Duration(seconds: 2));

      expect(find.byType(NavigationDestination), findsNWidgets(4));
    });

    testWidgets('tab labels are in Italian', (tester) async {
      await tester.pumpWidget(
        const ProviderScope(
          child: TaskTapApp(),
        ),
      );
      await tester.pumpAndSettle(const Duration(seconds: 2));

      expect(find.text('Oggi'), findsWidgets);
      expect(find.text('Interventi'), findsWidgets);
      expect(find.text('Rapportini'), findsWidgets);
      expect(find.text('Profilo'), findsWidgets);
    });
  });
}
