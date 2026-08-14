import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tasktap_mobile/core/theme/app_colors.dart';
import 'package:tasktap_mobile/core/theme/app_palette.dart';
import 'package:tasktap_mobile/core/theme/app_rack.dart';
import 'package:tasktap_mobile/core/theme/app_theme.dart';
import 'package:tasktap_mobile/core/widgets/rack.dart';

Widget _wrap(Widget child, {Brightness brightness = Brightness.light}) => MaterialApp(
  theme: buildAppTheme(brightness: brightness),
  home: Scaffold(body: child),
);

/// A cell inside a Column inside a scroll view — the shape almost every real call site has, and
/// the one that used to throw. Kept as the default harness rather than a special case so a
/// regression to `CrossAxisAlignment.stretch` fails these tests rather than the whole suite.
Widget _inScrollableColumn(Widget child) => SingleChildScrollView(
  child: Column(children: [child]),
);

void main() {
  group('RackCell', () {
    testWidgets('lays out under unbounded height', (tester) async {
      await tester.pumpWidget(_wrap(_inScrollableColumn(const RackCell(child: Text('x')))));

      expect(tester.takeException(), isNull);
      expect(find.text('x'), findsOneWidget);
    });

    testWidgets('is bone, flush on the rail edge, machined on the other three', (tester) async {
      await tester.pumpWidget(_wrap(const RackCell(child: Text('x'))));

      final decoration =
          tester
                  .widget<DecoratedBox>(
                    find.descendant(
                      of: find.byType(RackCell),
                      matching: find.byType(DecoratedBox),
                    ).first,
                  )
                  .decoration
              as BoxDecoration;

      expect(decoration.color, AppPalette.light.labelCard);
      expect(decoration.borderRadius, AppRack.cellShape);
      expect(
        (decoration.borderRadius! as BorderRadius).topLeft,
        Radius.zero,
        reason: 'the leading edge is butted against the rail',
      );
    });

    testWidgets('an unstrapped cell draws a graphite ledge', (tester) async {
      await tester.pumpWidget(_wrap(const RackCell(child: Text('x'))));
      expect(_ledgeColour(tester), AppPalette.light.ledge);
    });

    testWidgets('a strapped cell turns its ledge brand yellow', (tester) async {
      await tester.pumpWidget(_wrap(const RackCell(strapped: true, child: Text('x'))));
      expect(_ledgeColour(tester), AppColors.Y);
    });

    testWidgets('strapped wins over an explicit ledge colour', (tester) async {
      await tester.pumpWidget(
        _wrap(const RackCell(strapped: true, ledgeColor: Color(0xFF00FF00), child: Text('x'))),
      );
      expect(
        _ledgeColour(tester),
        AppColors.Y,
        reason: 'live outranks every other state a ledge can carry',
      );
    });

    testWidgets('a tappable cell does not swallow taps meant for its children', (tester) async {
      var cellTaps = 0;
      var childTaps = 0;

      await tester.pumpWidget(
        _wrap(
          RackCell(
            onTap: () => cellTaps++,
            child: Row(
              children: [
                const Expanded(child: Text('body')),
                TextButton(onPressed: () => childTaps++, child: const Text('azione')),
              ],
            ),
          ),
        ),
      );

      await tester.tap(find.text('azione'));
      await tester.pumpAndSettle();

      // The first arrangement of this widget layered an InkWell over the cell, which painted a
      // correct splash and ate every tap meant for a control inside it.
      expect(childTaps, 1);
      expect(cellTaps, 0);

      await tester.tap(find.text('body'));
      await tester.pumpAndSettle();
      expect(cellTaps, 1);
    });

    testWidgets('takes its materials from the dark palette under dark', (tester) async {
      await tester.pumpWidget(
        _wrap(const RackCell(child: Text('x')), brightness: Brightness.dark),
      );

      final decoration =
          tester
                  .widget<DecoratedBox>(
                    find.descendant(
                      of: find.byType(RackCell),
                      matching: find.byType(DecoratedBox),
                    ).first,
                  )
                  .decoration
              as BoxDecoration;

      expect(decoration.color, AppPalette.dark.labelCard);
      expect(_ledgeColour(tester), AppPalette.dark.ledge);
    });
  });

  group('Rack', () {
    testWidgets('draws the rail inside the existing page gutter', (tester) async {
      await tester.pumpWidget(_wrap(const Rack(child: SizedBox.expand())));

      final rail = tester.getRect(
        find.descendant(of: find.byType(Rack), matching: find.byType(DecoratedBox)).first,
      );

      expect(rail.left, AppRack.railInset);
      expect(rail.width, AppRack.railWidth);
      // The whole reason the rail costs no layout: it ends before the 19dp gutter every screen
      // already indents its content by.
      expect(rail.right + AppRack.railToCell, AppRack.railColumn);
      expect(AppRack.railColumn, 19);
    });

    testWidgets('draws nothing when the surface holds no rack', (tester) async {
      await tester.pumpWidget(_wrap(const Rack(visible: false, child: Text('x'))));

      expect(find.descendant(of: find.byType(Rack), matching: find.byType(DecoratedBox)), findsNothing);
      expect(find.text('x'), findsOneWidget);
    });
  });

  group('ShadowBoard', () {
    testWidgets('names what is missing, and reads it out as one phrase', (tester) async {
      final handle = tester.ensureSemantics();

      await tester.pumpWidget(
        _wrap(
          const ShadowBoard(
            label: 'Nessun rapportino in coda',
            reason: 'La sincronizzazione non è ancora riuscita.',
          ),
        ),
      );

      expect(find.text('Nessun rapportino in coda'), findsOneWidget);
      expect(find.text('La sincronizzazione non è ancora riuscita.'), findsOneWidget);
      expect(
        tester.getSemantics(find.byType(ShadowBoard)),
        matchesSemantics(
          label: 'Nessun rapportino in coda. La sincronizzazione non è ancora riuscita.',
        ),
      );

      handle.dispose();
    });

    testWidgets('an ordinary empty slot states no reason', (tester) async {
      await tester.pumpWidget(_wrap(const ShadowBoard(label: 'Nessun materiale')));

      expect(find.text('Nessun materiale'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });
}

/// The ledge is the Positioned layer at the cell's leading edge.
Color? _ledgeColour(WidgetTester tester) {
  final positioned = tester.widget<Positioned>(
    find.descendant(of: find.byType(RackCell), matching: find.byType(Positioned)).first,
  );
  final box = (positioned.child as DecoratedBox).decoration as BoxDecoration;
  return box.color;
}
