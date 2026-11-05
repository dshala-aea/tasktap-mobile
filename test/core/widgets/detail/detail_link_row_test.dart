import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tasktap_mobile/core/theme/app_theme.dart';
import 'package:tasktap_mobile/core/widgets/detail/detail_link_row.dart';

Widget _app(Widget child) => MaterialApp(
  theme: buildAppTheme(brightness: Brightness.light),
  home: Scaffold(body: child),
);

void main() {
  group('DetailLinkRow', () {
    testWidgets('renders a section name and its mono meta', (tester) async {
      await tester.pumpWidget(
        _app(
          const DetailLinkRow(
            title: 'Relazioni',
            meta: '12 sedi · 4 contratti · 3 referenti',
          ),
        ),
      );

      expect(find.text('Relazioni'), findsOneWidget);
      expect(find.text('12 SEDI · 4 CONTRATTI · 3 REFERENTI'), findsOneWidget);
    });

    testWidgets('tapping the row calls onTap and the target is at least 44px', (
      tester,
    ) async {
      var tapped = false;

      await tester.pumpWidget(
        _app(
          DetailLinkRow(
            title: 'Movimenti',
            meta: 'Carichi, scarichi, rettifiche',
            onTap: () => tapped = true,
          ),
        ),
      );

      expect(
        tester.getSize(find.byType(DetailLinkRow)).height,
        greaterThanOrEqualTo(44),
      );

      await tester.tap(find.text('Movimenti'));
      expect(tapped, isTrue);
    });

    testWidgets('showDivider false draws no bottom rule', (tester) async {
      await tester.pumpWidget(
        _app(const DetailLinkRow(title: 'Ultima', showDivider: false)),
      );

      final container = tester.widget<Container>(
        find
            .descendant(
              of: find.byType(DetailLinkRow),
              matching: find.byType(Container),
            )
            .first,
      );
      final decoration = container.decoration as BoxDecoration;
      expect(decoration.border, isNull);
    });

    testWidgets('a custom trailing widget replaces the meta text', (
      tester,
    ) async {
      await tester.pumpWidget(
        _app(
          const DetailLinkRow(
            title: 'Scadenze',
            meta: 'ignorata',
            trailing: Text('31/12/2026'),
          ),
        ),
      );

      expect(find.text('31/12/2026'), findsOneWidget);
      expect(find.text('IGNORATA'), findsNothing);
    });
  });
}
