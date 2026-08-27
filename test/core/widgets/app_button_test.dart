import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tasktap_mobile/core/theme/app_colors.dart';
import 'package:tasktap_mobile/core/theme/app_vetro_palette.dart';
import 'package:tasktap_mobile/core/widgets/app_button.dart';

Widget _wrap(Widget child) => MaterialApp(home: Scaffold(body: child));

void main() {
  group('AppButton variants', () {
    testWidgets('primary renders and is tappable', (tester) async {
      var tapped = false;
      await tester.pumpWidget(_wrap(AppButton(label: 'Salva', onPressed: () => tapped = true)));
      expect(find.text('Salva'), findsOneWidget);
      await tester.tap(find.text('Salva'));
      expect(tapped, isTrue);
    });

    testWidgets('primary has the Vetro tint gradient background', (tester) async {
      await tester.pumpWidget(_wrap(AppButton(label: 'Test', onPressed: () {})));
      final container = tester.widget<DecoratedBox>(
        find.descendant(of: find.byType(AppButton), matching: find.byType(DecoratedBox)).first,
      );
      final box = container.decoration as BoxDecoration;
      final gradient = box.gradient as LinearGradient;
      expect(gradient.colors, [AppVetroPalette.light.tint, AppVetroPalette.light.tintStrong]);
    });

    testWidgets('secondary variant renders', (tester) async {
      await tester.pumpWidget(_wrap(AppButton.secondary(label: 'Annulla', onPressed: () {})));
      expect(find.text('Annulla'), findsOneWidget);
      // BG3 background
      final container = tester.widget<DecoratedBox>(
        find.descendant(of: find.byType(AppButton), matching: find.byType(DecoratedBox)).first,
      );
      final box = container.decoration as BoxDecoration;
      expect(box.color, equals(AppColors.BG3));
    });

    testWidgets('dark variant has DARK background', (tester) async {
      await tester.pumpWidget(_wrap(AppButton.dark(label: 'Dark', onPressed: () {})));
      final container = tester.widget<DecoratedBox>(
        find.descendant(of: find.byType(AppButton), matching: find.byType(DecoratedBox)).first,
      );
      final box = container.decoration as BoxDecoration;
      expect(box.color, equals(AppColors.DARK));
    });

    testWidgets('ghost variant renders without background colour', (tester) async {
      await tester.pumpWidget(_wrap(AppButton.ghost(label: 'Salta', onPressed: () {})));
      expect(find.text('Salta'), findsOneWidget);
      final container = tester.widget<DecoratedBox>(
        find.descendant(of: find.byType(AppButton), matching: find.byType(DecoratedBox)).first,
      );
      final box = container.decoration as BoxDecoration;
      expect(box.color, equals(Colors.transparent));
    });

    testWidgets('danger variant has REDSOFT background', (tester) async {
      await tester.pumpWidget(_wrap(AppButton.danger(label: 'Elimina', onPressed: () {})));
      final container = tester.widget<DecoratedBox>(
        find.descendant(of: find.byType(AppButton), matching: find.byType(DecoratedBox)).first,
      );
      final box = container.decoration as BoxDecoration;
      expect(box.color, equals(AppColors.REDSOFT));
    });
  });

  group('AppButton sizes', () {
    testWidgets('lg size renders label', (tester) async {
      await tester.pumpWidget(
        _wrap(AppButton(label: 'Large', onPressed: () {}, size: AppButtonSize.lg)),
      );
      expect(find.text('Large'), findsOneWidget);
    });

    testWidgets('md size renders label', (tester) async {
      await tester.pumpWidget(
        _wrap(AppButton(label: 'Medium', onPressed: () {}, size: AppButtonSize.md)),
      );
      expect(find.text('Medium'), findsOneWidget);
    });

    testWidgets('sm size renders label', (tester) async {
      await tester.pumpWidget(
        _wrap(AppButton(label: 'Small', onPressed: () {}, size: AppButtonSize.sm)),
      );
      expect(find.text('Small'), findsOneWidget);
    });
  });

  group('AppButton options', () {
    testWidgets('icon appears when provided', (tester) async {
      await tester.pumpWidget(
        _wrap(
          AppButton(label: 'Con icona', onPressed: () {}, icon: const Icon(Icons.add, size: 16)),
        ),
      );
      expect(find.byIcon(Icons.add), findsOneWidget);
      expect(find.text('Con icona'), findsOneWidget);
    });

    testWidgets('fullWidth wraps in SizedBox.expand', (tester) async {
      await tester.pumpWidget(_wrap(AppButton(label: 'Full', onPressed: () {}, fullWidth: true)));
      expect(find.byType(SizedBox), findsWidgets);
    });

    testWidgets('isLoading shows CircularProgressIndicator', (tester) async {
      await tester.pumpWidget(_wrap(AppButton(label: 'Loading', isLoading: true)));
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
    });

    testWidgets('disabled (onPressed null) still renders', (tester) async {
      await tester.pumpWidget(_wrap(const AppButton(label: 'Disabled')));
      expect(find.text('Disabled'), findsOneWidget);
    });

    testWidgets('minimum touch target is at least 44pt', (tester) async {
      await tester.pumpWidget(
        _wrap(AppButton(label: 'X', onPressed: () {}, size: AppButtonSize.sm, fullWidth: false)),
      );
      final constraints = tester.widget<ConstrainedBox>(
        find.descendant(of: find.byType(AppButton), matching: find.byType(ConstrainedBox)).first,
      );
      expect(constraints.constraints.minHeight, greaterThanOrEqualTo(44));
      expect(constraints.constraints.minWidth, greaterThanOrEqualTo(44));
    });

    testWidgets('backward-compat: AppButton.danger named constructor', (tester) async {
      var tapped = false;
      await tester.pumpWidget(
        _wrap(
          AppButton.danger(
            label: 'Disconnetti',
            icon: const Icon(Icons.logout, size: 18),
            onPressed: () => tapped = true,
          ),
        ),
      );
      expect(find.text('Disconnetti'), findsOneWidget);
      expect(find.byIcon(Icons.logout), findsOneWidget);
      await tester.tap(find.text('Disconnetti'));
      expect(tapped, isTrue);
    });
  });
}
