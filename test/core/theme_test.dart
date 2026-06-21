import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tasktap_mobile/core/theme/app_colors.dart';
import 'package:tasktap_mobile/core/theme/app_theme.dart';
import 'package:tasktap_mobile/core/theme/status_colors.dart';

void main() {
  // google_fonts loads fonts asynchronously; using testWidgets gives us a
  // binding + fake-async environment so font-load callbacks don't escape.
  group('buildAppTheme', () {
    testWidgets('returns a valid ThemeData', (tester) async {
      final theme = buildAppTheme();
      expect(theme, isA<ThemeData>());
    });

    testWidgets('primary color is brand yellow #FFF10E', (tester) async {
      final theme = buildAppTheme();
      expect(theme.colorScheme.primary, equals(AppColors.brand));
    });

    testWidgets('onPrimary color is dark for contrast', (tester) async {
      final theme = buildAppTheme();
      expect(theme.colorScheme.onPrimary, equals(AppColors.onBrand));
    });

    testWidgets('brightness is light', (tester) async {
      final theme = buildAppTheme();
      expect(theme.colorScheme.brightness, equals(Brightness.light));
    });

    testWidgets('useMaterial3 is true', (tester) async {
      final theme = buildAppTheme();
      expect(theme.useMaterial3, isTrue);
    });

    testWidgets('error color is set', (tester) async {
      final theme = buildAppTheme();
      expect(theme.colorScheme.error, equals(AppColors.error));
    });
  });

  // Pure Dart tests — no Flutter binding needed, no google_fonts calls.
  group('statusColor', () {
    test('Bozza maps to grey background', () {
      final pair = statusColor(ReportStato.bozza);
      expect(pair.background, equals(AppColors.statusBozza));
      expect(pair.foreground, equals(AppColors.onStatusBozza));
    });

    test('Inviato maps to blue background', () {
      final pair = statusColor(ReportStato.inviato);
      expect(pair.background, equals(AppColors.statusInviato));
      expect(pair.foreground, equals(AppColors.onStatusInviato));
    });

    test('Controllato maps to amber background', () {
      final pair = statusColor(ReportStato.controllato);
      expect(pair.background, equals(AppColors.statusControllato));
      expect(pair.foreground, equals(AppColors.onStatusControllato));
    });

    test('Fatturato maps to green background', () {
      final pair = statusColor(ReportStato.fatturato);
      expect(pair.background, equals(AppColors.statusFatturato));
      expect(pair.foreground, equals(AppColors.onStatusFatturato));
    });

    test('Annullato maps to red background', () {
      final pair = statusColor(ReportStato.annullato);
      expect(pair.background, equals(AppColors.statusAnnullato));
      expect(pair.foreground, equals(AppColors.onStatusAnnullato));
    });

    test('all statuses return non-transparent colors', () {
      for (final stato in ReportStato.values) {
        final pair = statusColor(stato);
        expect(
          (pair.background.a * 255.0).round(),
          greaterThan(0),
          reason: 'background for $stato should be opaque',
        );
        expect(
          (pair.foreground.a * 255.0).round(),
          greaterThan(0),
          reason: 'foreground for $stato should be opaque',
        );
      }
    });

    test('statoLabel returns Italian string for each stato', () {
      expect(statoLabel(ReportStato.bozza), 'Bozza');
      expect(statoLabel(ReportStato.inviato), 'Inviato');
      expect(statoLabel(ReportStato.controllato), 'Controllato');
      expect(statoLabel(ReportStato.fatturato), 'Fatturato');
      expect(statoLabel(ReportStato.annullato), 'Annullato');
    });
  });

  group('AppColors', () {
    test('brand yellow is #FFF10E', () {
      expect(AppColors.brand, equals(const Color(0xFFFFF10E)));
    });

    test('onBrand has sufficient contrast (near-black)', () {
      // onBrand = #111111, luminance very low
      expect(AppColors.onBrand.computeLuminance(), lessThan(0.05));
    });
  });
}
