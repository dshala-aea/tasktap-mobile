import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tasktap_mobile/core/theme/app_colors.dart';
import 'package:tasktap_mobile/core/widgets/app_tabs.dart';

Widget _wrap(Widget child) => MaterialApp(
  home: Scaffold(body: SizedBox(width: 400, child: child)),
);

void main() {
  group('AppTabs', () {
    const tabs = [
      AppTab(label: 'Tutti', count: 12),
      AppTab(label: 'Aperti'),
      AppTab(label: 'Chiusi', count: 3),
    ];

    testWidgets('renders all tab labels', (tester) async {
      await tester.pumpWidget(_wrap(AppTabs(tabs: tabs, selectedIndex: 0, onSelected: (_) {})));
      expect(find.text('Tutti'), findsOneWidget);
      expect(find.text('Aperti'), findsOneWidget);
      expect(find.text('Chiusi'), findsOneWidget);
    });

    testWidgets('active tab (index 0) has DARK color text', (tester) async {
      await tester.pumpWidget(_wrap(AppTabs(tabs: tabs, selectedIndex: 0, onSelected: (_) {})));
      final textWidgets = tester.widgetList<Text>(find.text('Tutti'));
      final activeText = textWidgets.first;
      expect(activeText.style?.color, equals(AppColors.DARK));
    });

    testWidgets('inactive tab has MUTED color text', (tester) async {
      await tester.pumpWidget(_wrap(AppTabs(tabs: tabs, selectedIndex: 0, onSelected: (_) {})));
      final textWidgets = tester.widgetList<Text>(find.text('Aperti'));
      final inactiveText = textWidgets.first;
      expect(inactiveText.style?.color, equals(AppColors.MUTED));
    });

    testWidgets('tapping a tab reports its index', (tester) async {
      int? selected;
      await tester.pumpWidget(
        _wrap(AppTabs(tabs: tabs, selectedIndex: 0, onSelected: (i) => selected = i)),
      );
      await tester.tap(find.text('Chiusi'));
      expect(selected, equals(2));
    });

    testWidgets('changing selectedIndex changes active tab', (tester) async {
      await tester.pumpWidget(_wrap(AppTabs(tabs: tabs, selectedIndex: 1, onSelected: (_) {})));
      final apertiText = tester.widget<Text>(find.text('Aperti'));
      expect(apertiText.style?.color, equals(AppColors.DARK));
      final tuttiText = tester.widget<Text>(find.text('Tutti'));
      expect(tuttiText.style?.color, equals(AppColors.MUTED));
    });

    testWidgets('count pill renders for tabs with a count', (tester) async {
      await tester.pumpWidget(_wrap(AppTabs(tabs: tabs, selectedIndex: 0, onSelected: (_) {})));
      // count 12 and 3 should appear; Aperti has no count
      expect(find.text('12'), findsOneWidget);
      expect(find.text('3'), findsOneWidget);
    });
  });

  _overflowingStripTests();
}

/// A tab strip that runs past the frame has to behave like one.
///
/// The ticket screen has seven tabs and a phone fits about four. The strip gave no sign the other
/// three existed, and opening it on one of them — which happens on any return to a screen that
/// remembers where you were — left it scrolled to the start with the selected tab off-frame.
const _many = [
  AppTab(label: 'Report'),
  AppTab(label: 'Controllo'),
  AppTab(label: 'Allegati'),
  AppTab(label: 'Ore'),
  AppTab(label: 'Pianificazioni'),
  AppTab(label: 'Fabbisogno'),
  AppTab(label: 'Storico'),
];

void _overflowingStripTests() {
  group('AppTabs — a strip wider than the phone', () {
    Widget wrap(Widget child) => MaterialApp(home: Scaffold(body: child));

    testWidgets('opens scrolled to the selected tab, not to the start', (tester) async {
      await tester.binding.setSurfaceSize(const Size(390, 844));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(wrap(AppTabs(tabs: _many, selectedIndex: 6, onSelected: (_) {})));
      await tester.pumpAndSettle();

      final storico = tester.getRect(find.text('Storico'));
      expect(storico.left, greaterThanOrEqualTo(0));
      expect(storico.right, lessThanOrEqualTo(390));
    });

    testWidgets('a strip that already fits is not shoved around', (tester) async {
      // Two tabs have nowhere to go; the reveal must be a no-op rather than a jolt.
      await tester.binding.setSurfaceSize(const Size(390, 844));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(
        wrap(
          AppTabs(
            tabs: const [AppTab(label: 'Tutti'), AppTab(label: 'Aperti')],
            selectedIndex: 1,
            onSelected: (_) {},
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(tester.getRect(find.text('Tutti')).left, greaterThanOrEqualTo(0));
      expect(tester.takeException(), isNull);
    });
  });
}
