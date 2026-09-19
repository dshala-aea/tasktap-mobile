import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tasktap_mobile/core/theme/app_colors.dart';
import 'package:tasktap_mobile/core/widgets/bottom_nav.dart';

Widget _wrap(Widget child) => MaterialApp(home: Scaffold(body: child));

void main() {
  group('AppBottomNav', () {
    testWidgets('active tab shows its label; inactive tabs are icon-only', (tester) async {
      await tester.pumpWidget(_wrap(AppBottomNav(currentIndex: 0, onTap: (_) {})));
      await tester.pumpAndSettle();

      // Only the active (Dashboard) label is shown.
      expect(find.text('Dashboard'), findsOneWidget);
      expect(find.text('Ticket'), findsNothing);
      expect(find.text('Cantieri'), findsNothing);
      expect(find.text('Calendario'), findsNothing);
      expect(find.text('Altro'), findsNothing);
    });

    /// The bar has to fit the phone it is on.
    ///
    /// Padding + icon + the active tab's label came to two pixels more than a 5.9" screen has,
    /// so a striped overflow bar sat across the bottom of every screen on the device — and two
    /// pixels is the best case: the same layout at a larger system font size overflows by far
    /// more. Regression for the RenderFlex exception seen on a Mi A2.
    testWidgets('fits a narrow phone without overflowing', (tester) async {
      // The width the failing device reported for this Row, and a text scale a person with poor
      // eyesight would actually set.
      tester.view.physicalSize = const Size(720, 1440);
      tester.view.devicePixelRatio = 2.0;
      addTearDown(tester.view.reset);

      for (final scale in const [1.0, 1.3]) {
        await tester.pumpWidget(
          MediaQuery(
            data: MediaQueryData(textScaler: TextScaler.linear(scale)),
            child: _wrap(AppBottomNav(currentIndex: 0, onTap: (_) {})),
          ),
        );
        await tester.pumpAndSettle();

        expect(
          tester.takeException(),
          isNull,
          reason: 'the nav bar overflowed at text scale $scale',
        );
      }
    });

    testWidgets('changing currentIndex moves the active label', (tester) async {
      await tester.pumpWidget(_wrap(AppBottomNav(currentIndex: 1, onTap: (_) {})));
      await tester.pumpAndSettle();
      expect(find.text('Ticket'), findsOneWidget);
      expect(find.text('Dashboard'), findsNothing);
    });

    testWidgets('renders all 5 default tab icons', (tester) async {
      await tester.pumpWidget(_wrap(AppBottomNav(currentIndex: 0, onTap: (_) {})));
      await tester.pumpAndSettle();
      expect(find.byIcon(AppBottomNavIcons.dashboard), findsOneWidget);
      expect(find.byIcon(AppBottomNavIcons.ticket), findsOneWidget);
      expect(find.byIcon(AppBottomNavIcons.cantieri), findsOneWidget);
      expect(find.byIcon(AppBottomNavIcons.calendario), findsOneWidget);
      expect(find.byIcon(AppBottomNavIcons.altro), findsOneWidget);
    });

    testWidgets('tapping a tab reports its index', (tester) async {
      int? tapped;
      await tester.pumpWidget(_wrap(AppBottomNav(currentIndex: 0, onTap: (i) => tapped = i)));
      await tester.pumpAndSettle();
      await tester.tap(find.byIcon(AppBottomNavIcons.calendario));
      expect(tapped, equals(3));
    });

    testWidgets('active tab background is a flat stamp-red fill', (tester) async {
      await tester.pumpWidget(_wrap(AppBottomNav(currentIndex: 0, onTap: (_) {})));
      await tester.pumpAndSettle();

      final hasFlatFill = tester
          .widgetList<AnimatedContainer>(find.byType(AnimatedContainer))
          .any((c) {
            final d = c.decoration;
            if (d is! BoxDecoration) return false;
            return d.gradient == null && d.color == AppColors.Y;
          });
      expect(hasFlatFill, isTrue);
    });

    testWidgets('AppBottomNav has no BackdropFilter and active tab is a flat fill', (
      tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            bottomNavigationBar: AppBottomNav(currentIndex: 0, onTap: (_) {}),
          ),
        ),
      );

      expect(find.byType(BackdropFilter), findsNothing);
    });

    /// Regression for the "nav fills the whole screen" bug: `Scaffold.bottomNavigationBar` hands
    /// its child a LOOSE (not tight, but still bounded/finite) height constraint — up to the full
    /// screen height. `RenderPositionedBox` (what `Align` and `Center` both are) expands to fill
    /// ANY bounded constraint, not just an unbounded one, so without an explicit cap the nav
    /// silently grew to fill that whole loose bound. Mounted exactly like `home_shell.dart` does
    /// it (bottomNavigationBar + extendBody, with real body content competing for the same
    /// space) so this catches the real constraint chain, not just the widget in isolation.
    testWidgets('stays a compact pill under Scaffold.bottomNavigationBar, does not fill the screen', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 3.0;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            extendBody: true,
            body: Container(color: Colors.white),
            bottomNavigationBar: AppBottomNav(currentIndex: 0, onTap: (_) {}),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final height = tester.getSize(find.byType(AppBottomNav)).height;
      expect(
        height,
        lessThan(120),
        reason: 'AppBottomNav rendered $height logical px tall — it should be a fixed-height '
            'pill (~74px incl. safe area/margins), not stretch to fill available space',
      );
    });

    test('defaultItems has Cantieri at index 2, not Timbra', () {
      expect(AppBottomNav.defaultItems[2].label, 'Cantieri');
      expect(
        AppBottomNav.defaultItems.map((i) => i.label),
        isNot(contains('Timbra')),
      );
    });
  });
}
