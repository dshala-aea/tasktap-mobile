import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tasktap_mobile/core/theme/app_colors.dart';
import 'package:tasktap_mobile/core/theme/app_palette.dart';
import 'package:tasktap_mobile/core/theme/app_rack.dart';
import 'package:tasktap_mobile/core/widgets/app_card.dart';

Widget _wrap(Widget child) => MaterialApp(home: Scaffold(body: child));

void main() {
  group('AppCard', () {
    testWidgets('renders its child', (tester) async {
      await tester.pumpWidget(_wrap(const AppCard(child: Text('contenuto'))));
      expect(find.text('contenuto'), findsOneWidget);
    });

    testWidgets('is a cell: bone label card, flush leading edge, no drop shadow', (tester) async {
      await tester.pumpWidget(_wrap(const AppCard(child: Text('x'))));
      final box =
          tester
                  .widget<DecoratedBox>(
                    find
                        .descendant(of: find.byType(AppCard), matching: find.byType(DecoratedBox))
                        .first,
                  )
                  .decoration
              as BoxDecoration;

      // A card was BG1 with a soft shadow and a 14px radius — the moulded rounded-card idiom.
      // A cell is the bone label card, square where it butts the rail, machined on the other
      // three corners, and carries no shadow at all: depth is the ledge, which survives a dark
      // ground and direct sunlight where a 10%-black shadow does not.
      expect(box.color, equals(AppPalette.light.labelCard));
      expect(box.boxShadow, isNull);
      expect(box.borderRadius, equals(AppRack.cellShape));
    });

    testWidgets('honours a custom background color', (tester) async {
      await tester.pumpWidget(
        _wrap(const AppCard(backgroundColor: AppColors.WHITE, child: Text('x'))),
      );
      final box =
          tester
                  .widget<DecoratedBox>(
                    find
                        .descendant(of: find.byType(AppCard), matching: find.byType(DecoratedBox))
                        .first,
                  )
                  .decoration
              as BoxDecoration;
      expect(box.color, equals(AppColors.WHITE));
    });

    testWidgets('pressable variant fires onTap', (tester) async {
      var tapped = false;
      await tester.pumpWidget(
        _wrap(AppCard.pressable(onTap: () => tapped = true, child: const Text('tap'))),
      );
      await tester.tap(find.text('tap'));
      expect(tapped, isTrue);
    });
  });
}
