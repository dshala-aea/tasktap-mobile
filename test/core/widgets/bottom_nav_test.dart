import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tasktap_mobile/core/theme/app_colors.dart';
import 'package:tasktap_mobile/core/widgets/bottom_nav.dart';

Widget _wrap(Widget child) => MaterialApp(home: Scaffold(body: child));

void main() {
  group('AppBottomNav', () {
    testWidgets('active tab shows its label; inactive tabs are icon-only',
        (tester) async {
      await tester.pumpWidget(_wrap(
        AppBottomNav(currentIndex: 0, onTap: (_) {}),
      ));
      await tester.pumpAndSettle();

      // Only the active (Dashboard) label is shown.
      expect(find.text('Dashboard'), findsOneWidget);
      expect(find.text('Ticket'), findsNothing);
      expect(find.text('Timbra'), findsNothing);
      expect(find.text('Calendario'), findsNothing);
      expect(find.text('Altro'), findsNothing);
    });

    testWidgets('changing currentIndex moves the active label', (tester) async {
      await tester.pumpWidget(_wrap(
        AppBottomNav(currentIndex: 1, onTap: (_) {}),
      ));
      await tester.pumpAndSettle();
      expect(find.text('Ticket'), findsOneWidget);
      expect(find.text('Dashboard'), findsNothing);
    });

    testWidgets('renders all 5 default tab icons', (tester) async {
      await tester.pumpWidget(_wrap(
        AppBottomNav(currentIndex: 0, onTap: (_) {}),
      ));
      await tester.pumpAndSettle();
      expect(find.byIcon(AppBottomNavIcons.dashboard), findsOneWidget);
      expect(find.byIcon(AppBottomNavIcons.ticket), findsOneWidget);
      expect(find.byIcon(AppBottomNavIcons.timbra), findsOneWidget);
      expect(find.byIcon(AppBottomNavIcons.calendario), findsOneWidget);
      expect(find.byIcon(AppBottomNavIcons.altro), findsOneWidget);
    });

    testWidgets('tapping a tab reports its index', (tester) async {
      int? tapped;
      await tester.pumpWidget(_wrap(
        AppBottomNav(currentIndex: 0, onTap: (i) => tapped = i),
      ));
      await tester.pumpAndSettle();
      await tester.tap(find.byIcon(AppBottomNavIcons.calendario));
      expect(tapped, equals(3));
    });

    testWidgets('active tab background is brand yellow', (tester) async {
      await tester.pumpWidget(_wrap(
        AppBottomNav(currentIndex: 0, onTap: (_) {}),
      ));
      await tester.pumpAndSettle();

      final hasYellow = tester
          .widgetList<AnimatedContainer>(find.byType(AnimatedContainer))
          .any((c) {
        final d = c.decoration;
        return d is BoxDecoration && d.color == AppColors.Y;
      });
      expect(hasYellow, isTrue);
    });
  });
}
