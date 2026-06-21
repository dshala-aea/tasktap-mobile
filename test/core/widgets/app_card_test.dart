import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tasktap_mobile/core/theme/app_colors.dart';
import 'package:tasktap_mobile/core/widgets/app_card.dart';

Widget _wrap(Widget child) => MaterialApp(home: Scaffold(body: child));

void main() {
  group('AppCard', () {
    testWidgets('renders its child', (tester) async {
      await tester.pumpWidget(_wrap(const AppCard(child: Text('contenuto'))));
      expect(find.text('contenuto'), findsOneWidget);
    });

    testWidgets('default background is BG1 with SH shadow', (tester) async {
      await tester.pumpWidget(_wrap(const AppCard(child: Text('x'))));
      final box = tester
          .widget<DecoratedBox>(
            find
                .descendant(
                  of: find.byType(AppCard),
                  matching: find.byType(DecoratedBox),
                )
                .first,
          )
          .decoration as BoxDecoration;
      expect(box.color, equals(AppColors.BG1));
      expect(box.boxShadow, equals(AppColors.SH));
      expect(box.borderRadius, equals(BorderRadius.circular(14)));
    });

    testWidgets('honours a custom background color', (tester) async {
      await tester.pumpWidget(_wrap(
        const AppCard(backgroundColor: AppColors.WHITE, child: Text('x')),
      ));
      final box = tester
          .widget<DecoratedBox>(
            find
                .descendant(
                  of: find.byType(AppCard),
                  matching: find.byType(DecoratedBox),
                )
                .first,
          )
          .decoration as BoxDecoration;
      expect(box.color, equals(AppColors.WHITE));
    });

    testWidgets('pressable variant fires onTap', (tester) async {
      var tapped = false;
      await tester.pumpWidget(_wrap(
        AppCard.pressable(onTap: () => tapped = true, child: const Text('tap')),
      ));
      await tester.tap(find.text('tap'));
      expect(tapped, isTrue);
    });
  });

  group('GlassCard', () {
    testWidgets('renders its child', (tester) async {
      await tester.pumpWidget(_wrap(
        const ColoredBox(
          color: Colors.black,
          child: GlassCard(child: Text('glass')),
        ),
      ));
      expect(find.text('glass'), findsOneWidget);
    });

    testWidgets('uses a translucent white gradient + 14px radius',
        (tester) async {
      await tester.pumpWidget(_wrap(
        const ColoredBox(
          color: Colors.black,
          child: GlassCard(child: Text('g')),
        ),
      ));
      final box = tester
          .widget<DecoratedBox>(
            find
                .descendant(
                  of: find.byType(GlassCard),
                  matching: find.byType(DecoratedBox),
                )
                .first,
          )
          .decoration as BoxDecoration;
      expect(box.gradient, isA<LinearGradient>());
      expect(box.borderRadius, equals(BorderRadius.circular(14)));
    });

    testWidgets('pressable variant fires onTap', (tester) async {
      var tapped = false;
      await tester.pumpWidget(_wrap(
        ColoredBox(
          color: Colors.black,
          child: GlassCard.pressable(
            onTap: () => tapped = true,
            child: const Text('tap'),
          ),
        ),
      ));
      await tester.tap(find.text('tap'));
      expect(tapped, isTrue);
    });
  });
}
