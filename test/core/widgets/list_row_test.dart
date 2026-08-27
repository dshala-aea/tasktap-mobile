// dart format width=100
// test/core/widgets/list_row_test.dart
//
// No prior coverage existed for this widget directly (only indirectly, through the ~40 screens
// that use it) — added alongside its Vetro rewrite: flat, hairline-separated rows instead of the
// bordered RackCell "drawer front", same shape ticket_list_screen's _TicketRow and
// rapportini_list_screen's _RapportinoRow already proved out.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tasktap_mobile/core/icons/app_lucide_icons.dart';
import 'package:tasktap_mobile/core/theme/app_theme.dart';
import 'package:tasktap_mobile/core/theme/app_vetro_palette.dart';
import 'package:tasktap_mobile/core/widgets/list_row.dart';

Widget _wrap(Widget child) =>
    MaterialApp(theme: buildAppTheme(brightness: Brightness.light), home: Scaffold(body: child));

/// The 3px leading stripe: first Container in the row whose decoration paints a solid color
/// (border-radius 3) — distinct from the row's own outer Container (no color, just a border).
Color? _stripeColor(WidgetTester tester) {
  final containers = tester.widgetList<Container>(
    find.descendant(of: find.byType(ListRow), matching: find.byType(Container)),
  );
  for (final c in containers) {
    final d = c.decoration;
    if (d is BoxDecoration && d.borderRadius == BorderRadius.circular(3)) {
      return d.color;
    }
  }
  return null;
}

void main() {
  group('ListRow', () {
    testWidgets('renders title, subtitle, leading and meta', (tester) async {
      await tester.pumpWidget(
        _wrap(
          const ListRow(
            leading: Icon(Icons.build),
            title: 'Tubo rame 15mm',
            subtitle: 'ART-001',
            meta: Text('12 pz'),
          ),
        ),
      );

      expect(find.text('Tubo rame 15mm'), findsOneWidget);
      expect(find.text('ART-001'), findsOneWidget);
      expect(find.text('12 pz'), findsOneWidget);
      expect(find.byIcon(Icons.build), findsOneWidget);
    });

    testWidgets('shows a trailing chevron only when tappable', (tester) async {
      await tester.pumpWidget(_wrap(const ListRow(title: 'Non tappabile')));
      expect(find.byIcon(LucideIcons.chevronRight), findsNothing);

      await tester.pumpWidget(_wrap(ListRow(title: 'Tappabile', onTap: () {})));
      await tester.pumpAndSettle();
      expect(find.byIcon(LucideIcons.chevronRight), findsOneWidget);
    });

    testWidgets('tapping the row calls onTap', (tester) async {
      var tapped = false;
      await tester.pumpWidget(_wrap(ListRow(title: 'Riga', onTap: () => tapped = true)));

      await tester.tap(find.text('Riga'));
      expect(tapped, isTrue);
    });

    testWidgets('showDivider true draws a bottom hairline; false draws none', (tester) async {
      await tester.pumpWidget(_wrap(const ListRow(title: 'Con divisore')));
      var container = tester.widget<Container>(
        find.descendant(of: find.byType(ListRow), matching: find.byType(Container)).first,
      );
      var decoration = container.decoration as BoxDecoration;
      expect(decoration.border, isNotNull);

      await tester.pumpWidget(_wrap(const ListRow(title: 'Ultima riga', showDivider: false)));
      container = tester.widget<Container>(
        find.descendant(of: find.byType(ListRow), matching: find.byType(Container)).first,
      );
      decoration = container.decoration as BoxDecoration;
      expect(decoration.border, isNull);
    });

    testWidgets('an ordinary row draws a transparent leading stripe', (tester) async {
      await tester.pumpWidget(_wrap(const ListRow(title: 'Ordinaria')));
      expect(_stripeColor(tester), Colors.transparent);
    });

    testWidgets('strapped turns the leading stripe the Vetro tint', (tester) async {
      await tester.pumpWidget(_wrap(const ListRow(title: 'In evidenza', strapped: true)));
      expect(_stripeColor(tester), AppVetroColors.tint);
    });

    testWidgets('an explicit ledgeColor tints the stripe when not strapped', (tester) async {
      const ledge = Color(0xFFFF3B30);
      await tester.pumpWidget(_wrap(const ListRow(title: 'Scaduta', ledgeColor: ledge)));
      expect(_stripeColor(tester), ledge);
    });

    testWidgets('strapped wins over an explicit ledgeColor', (tester) async {
      const ledge = Color(0xFFFF3B30);
      await tester.pumpWidget(
        _wrap(const ListRow(title: 'Entrambi', strapped: true, ledgeColor: ledge)),
      );
      expect(_stripeColor(tester), AppVetroColors.tint);
    });
  });
}
