import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tasktap_mobile/core/theme/app_colors.dart';
import 'package:tasktap_mobile/core/theme/app_vetro_palette.dart';
import 'package:tasktap_mobile/core/widgets/app_card.dart';
import 'package:tasktap_mobile/core/widgets/vetro_glass.dart';

Widget _wrap(Widget child) => MaterialApp(home: Scaffold(body: child));

void main() {
  group('AppCard', () {
    testWidgets('renders its child', (tester) async {
      await tester.pumpWidget(_wrap(const AppCard(child: Text('contenuto'))));
      expect(find.text('contenuto'), findsOneWidget);
    });

    testWidgets('is a Vetro glass panel: no drop shadow, glass fill by default', (tester) async {
      await tester.pumpWidget(_wrap(const AppCard(child: Text('x'))));

      expect(find.descendant(of: find.byType(AppCard), matching: find.byType(VetroGlass)), findsOneWidget);

      final box =
          tester
                  .widget<DecoratedBox>(
                    find
                        .descendant(of: find.byType(AppCard), matching: find.byType(DecoratedBox))
                        .first,
                  )
                  .decoration
              as BoxDecoration;

      // A card was BG1 with a soft shadow — depth as a moulded elevation. Glass carries no shadow
      // at all: depth is a translucent blur and a hairline border, which survives a dark ground
      // and direct sunlight where a 10%-black shadow does not.
      expect(box.color, equals(AppVetroPalette.light.glassFill));
      expect(box.boxShadow, isNull);
      expect(box.borderRadius, equals(const BorderRadius.all(Radius.circular(20))));
    });

    testWidgets('strapped turns the glass border the Vetro tint', (tester) async {
      await tester.pumpWidget(_wrap(const AppCard(strapped: true, child: Text('x'))));
      final box =
          tester
                  .widget<DecoratedBox>(
                    find
                        .descendant(of: find.byType(AppCard), matching: find.byType(DecoratedBox))
                        .first,
                  )
                  .decoration
              as BoxDecoration;
      expect(box.border, Border.all(color: AppVetroPalette.light.tint));
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
