import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tasktap_mobile/core/theme/app_colors.dart';
import 'package:tasktap_mobile/core/theme/app_palette.dart';
import 'package:tasktap_mobile/core/theme/app_rack.dart';
import 'package:tasktap_mobile/core/theme/app_theme.dart';
import 'package:tasktap_mobile/core/widgets/app_card.dart';

Widget _wrap(Widget child) => MaterialApp(home: Scaffold(body: child));

Widget _wrapThemed(Widget child, {required Brightness brightness}) =>
    MaterialApp(theme: buildAppTheme(brightness: brightness), home: Scaffold(body: child));

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
      //
      // Compared against AppPalette.light's own values, not the AppColors constants directly:
      // AppCard reads context.colors.surface/borderLight (themed, flips in dark mode — see the
      // dedicated dark-mode test below), which merely happen to equal SHEET/BL under the light
      // palette this unthemed MaterialApp falls back to.
      expect(box.color, equals(AppPalette.light.surface));
      expect(box.boxShadow, isNull);
      expect(box.borderRadius, equals(AppRack.freeShape));
      expect(box.border, equals(Border.all(color: AppPalette.light.borderLight, width: 1)));
    });

    testWidgets('reads its surface and border from the theme, flips in dark mode', (
      tester,
    ) async {
      await tester.pumpWidget(
        _wrapThemed(const AppCard(child: Text('x')), brightness: Brightness.dark),
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

      // The regression this test pins: AppCard used to read AppColors.SHEET/a hardcoded hex
      // directly, so a user flipping the app's real "Tema scuro" toggle would still see a bright
      // cream sheet against a dark background. Both fields must resolve to the dark palette, not
      // the light one.
      expect(box.color, equals(AppPalette.dark.surface));
      expect(box.color, isNot(equals(AppColors.SHEET)));
      expect(box.border, equals(Border.all(color: AppPalette.dark.borderLight, width: 1)));
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
