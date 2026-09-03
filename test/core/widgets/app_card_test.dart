import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tasktap_mobile/core/theme/app_colors.dart';
import 'package:tasktap_mobile/core/theme/app_rack.dart';
import 'package:tasktap_mobile/core/widgets/app_card.dart';

Widget _wrap(Widget child) => MaterialApp(home: Scaffold(body: child));

void main() {
  group('AppCard', () {
    testWidgets('renders its child', (tester) async {
      await tester.pumpWidget(_wrap(const AppCard(child: Text('contenuto'))));
      expect(find.text('contenuto'), findsOneWidget);
    });

    testWidgets('renders a flat sheet, no BackdropFilter', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(home: Scaffold(body: AppCard(child: Text('hi')))),
      );

      expect(find.byType(BackdropFilter), findsNothing);
      final decoratedBox = tester.widget<DecoratedBox>(find.byType(DecoratedBox).first);
      final decoration = decoratedBox.decoration as BoxDecoration;
      expect(decoration.color, AppColors.SHEET);
      expect(decoration.gradient, isNull);
    });

    testWidgets('is a flat sheet: no drop shadow, default hairline border', (tester) async {
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

      // A card was BG1 with a soft shadow — depth as a moulded elevation. The flat Documento sheet
      // carries no shadow at all: depth is a hairline border, which reads on a paper-flat ground.
      expect(box.color, equals(AppColors.SHEET));
      expect(box.boxShadow, isNull);
      expect(box.borderRadius, equals(AppRack.freeShape));
      expect(box.border, equals(Border.all(color: const Color(0xFFDED9CE), width: 1)));
    });

    testWidgets('strapped turns the border stamp-red', (tester) async {
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
      expect(box.border, Border.all(color: AppColors.Y));
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
