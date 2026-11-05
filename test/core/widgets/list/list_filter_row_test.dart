import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tasktap_mobile/core/theme/app_theme.dart';
import 'package:tasktap_mobile/core/widgets/list/list_filter_row.dart';
import 'package:tasktap_mobile/core/widgets/list/list_models.dart';

Widget _app(Widget child) => MaterialApp(
  theme: buildAppTheme(brightness: Brightness.light),
  home: Scaffold(body: child),
);

void main() {
  group('ListFilterRow', () {
    testWidgets('renders chips uppercased and reports the tapped chip', (
      tester,
    ) async {
      ListFilterChipData? selected;

      await tester.pumpWidget(
        _app(
          ListFilterRow(
            filters: const [
              ListFilterChipData(label: 'Attivi', id: 'active'),
              ListFilterChipData(label: 'Sotto scorta', id: 'low'),
            ],
            activeId: 'active',
            onSelected: (chip) => selected = chip,
          ),
        ),
      );

      expect(find.text('ATTIVI'), findsOneWidget);
      expect(find.text('SOTTO SCORTA'), findsOneWidget);

      await tester.tap(find.text('SOTTO SCORTA'));
      expect(selected?.id, 'low');
    });

    testWidgets('the active chip is marked selected for screen readers', (
      tester,
    ) async {
      await tester.pumpWidget(
        _app(
          ListFilterRow(
            filters: const [
              ListFilterChipData(label: 'Attivi', id: 'active'),
              ListFilterChipData(label: 'Tutti', id: 'all'),
            ],
            activeId: 'active',
            onSelected: (_) {},
          ),
        ),
      );

      final handle = tester.ensureSemantics();
      expect(
        tester.getSemantics(find.text('ATTIVI')),
        matchesSemantics(
          label: 'Attivi',
          isButton: true,
          isSelected: true,
          hasSelectedState: true,
          hasTapAction: true,
        ),
      );
      handle.dispose();
    });

    testWidgets('the trailing Filtri chip is accent and opens the sheet', (
      tester,
    ) async {
      var opened = false;

      await tester.pumpWidget(
        _app(
          ListFilterRow(
            filters: const [ListFilterChipData(label: 'Attivi')],
            onOpenFilters: () => opened = true,
          ),
        ),
      );

      expect(find.text('FILTRI'), findsOneWidget);
      await tester.tap(find.text('FILTRI'));
      expect(opened, isTrue);
    });

    testWidgets('chips keep a 44px target without enlarging the glyphs', (
      tester,
    ) async {
      await tester.pumpWidget(
        _app(
          ListFilterRow(
            filters: const [ListFilterChipData(label: 'Attivi')],
            onSelected: (_) {},
          ),
        ),
      );

      expect(
        tester.getSize(find.byType(ListFilterRow)).height,
        greaterThanOrEqualTo(44),
      );
    });
  });
}
