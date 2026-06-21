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

    testWidgets('primary color is brand yellow Y #FFF10E', (tester) async {
      final theme = buildAppTheme();
      expect(theme.colorScheme.primary, equals(AppColors.Y));
    });

    testWidgets('onPrimary color is DARK for contrast', (tester) async {
      final theme = buildAppTheme();
      expect(theme.colorScheme.onPrimary, equals(AppColors.DARK));
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
  group('statusColor (string API)', () {
    test('Bozza maps to light-grey background', () {
      final pair = statusColor('Bozza');
      expect(pair.background, equals(const Color(0xFFF5F5F5)));
      expect(pair.foreground, equals(const Color(0xFF666666)));
    });

    test('Inviata maps to blue background', () {
      final pair = statusColor('Inviata');
      expect(pair.background, equals(const Color(0xFFDCE8FF)));
      expect(pair.foreground, equals(const Color(0xFF1D4ED8)));
    });

    test('In corso maps to AMBER background', () {
      final pair = statusColor('In corso');
      expect(pair.background, equals(AppColors.AMBER));
      expect(pair.foreground, equals(const Color(0xFF000000)));
    });

    test('Completato maps to green background', () {
      final pair = statusColor('Completato');
      expect(pair.background, equals(const Color(0xFFDAF2E0)));
      expect(pair.foreground, equals(const Color(0xFF1E7A3A)));
    });

    test('Annullato maps to red-soft background', () {
      final pair = statusColor('Annullato');
      expect(pair.background, equals(const Color(0xFFFFDCDC)));
      expect(pair.foreground, equals(const Color(0xFFAA0000)));
    });

    test('Pagata maps to green background', () {
      final pair = statusColor('Pagata');
      expect(pair.background, equals(const Color(0xFFDAF2E0)));
      expect(pair.foreground, equals(const Color(0xFF1E7A3A)));
    });

    test('Scaduta maps to red-soft background', () {
      final pair = statusColor('Scaduta');
      expect(pair.background, equals(const Color(0xFFFFDCDC)));
    });

    test('Sospeso maps to red-soft background', () {
      final pair = statusColor('Sospeso');
      expect(pair.background, equals(const Color(0xFFFFDCDC)));
    });

    test('Attivo maps to green background', () {
      final pair = statusColor('Attivo');
      expect(pair.background, equals(const Color(0xFFDAF2E0)));
    });

    test('all 13 statuses return non-transparent colors', () {
      final statuses = [
        'Aperto',
        'In corso',
        'In pausa',
        'In attesa',
        'Completato',
        'Chiuso',
        'Annullato',
        'Bozza',
        'Inviata',
        'Pagata',
        'Scaduta',
        'Sospeso',
        'Attivo',
      ];
      for (final s in statuses) {
        final pair = statusColor(s);
        expect(
          (pair.background.a * 255.0).round(),
          greaterThan(0),
          reason: 'background for $s should be opaque',
        );
        expect(
          (pair.foreground.a * 255.0).round(),
          greaterThan(0),
          reason: 'foreground for $s should be opaque',
        );
      }
    });
  });

  group('statusColorFromStato (legacy enum API)', () {
    test('bozza maps to grey background', () {
      final pair = statusColorFromStato(ReportStato.bozza);
      expect(pair.background, equals(AppColors.statusBozza));
      expect(pair.foreground, equals(AppColors.onStatusBozza));
    });

    test('inviato maps to blue background', () {
      final pair = statusColorFromStato(ReportStato.inviato);
      expect(pair.background, equals(AppColors.statusInviato));
      expect(pair.foreground, equals(AppColors.onStatusInviato));
    });

    test('controllato maps to amber background', () {
      final pair = statusColorFromStato(ReportStato.controllato);
      expect(pair.background, equals(AppColors.statusControllato));
      expect(pair.foreground, equals(AppColors.onStatusControllato));
    });

    test('fatturato maps to green background', () {
      final pair = statusColorFromStato(ReportStato.fatturato);
      expect(pair.background, equals(AppColors.statusFatturato));
      expect(pair.foreground, equals(AppColors.onStatusFatturato));
    });

    test('annullato maps to red background', () {
      final pair = statusColorFromStato(ReportStato.annullato);
      expect(pair.background, equals(AppColors.statusAnnullato));
      expect(pair.foreground, equals(AppColors.onStatusAnnullato));
    });

    test('all statuses return non-transparent colors', () {
      for (final stato in ReportStato.values) {
        final pair = statusColorFromStato(stato);
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
      expect(statoLabel(ReportStato.inviato), 'Inviata');
      expect(statoLabel(ReportStato.controllato), 'Controllato');
      expect(statoLabel(ReportStato.fatturato), 'Pagata');
      expect(statoLabel(ReportStato.annullato), 'Annullato');
    });
  });

  group('AppColors', () {
    test('brand yellow Y is #FFF10E', () {
      expect(AppColors.Y, equals(const Color(0xFFFFF10E)));
    });

    test('brand alias equals Y', () {
      expect(AppColors.brand, equals(AppColors.Y));
    });

    test('DARK has sufficient contrast (near-black)', () {
      expect(AppColors.DARK.computeLuminance(), lessThan(0.10));
    });

    test('onBrand alias equals DARK', () {
      expect(AppColors.onBrand, equals(AppColors.DARK));
    });

    test('AMBER is rgb(255,178,0)', () {
      expect(AppColors.AMBER, equals(const Color(0xFFFFB200)));
    });

    test('GREEN is #4caf50', () {
      expect(AppColors.GREEN, equals(const Color(0xFF4CAF50)));
    });

    test('BLUE is #2563eb', () {
      expect(AppColors.BLUE, equals(const Color(0xFF2563EB)));
    });

    test('CYAN is #06AED5', () {
      expect(AppColors.CYAN, equals(const Color(0xFF06AED5)));
    });

    test('BG1 is rgb(250,250,250)', () {
      expect(AppColors.BG1, equals(const Color(0xFFFAFAFA)));
    });

    test('DIV is rgb(212,212,212)', () {
      expect(AppColors.DIV, equals(const Color(0xFFD4D4D4)));
    });

    test('SH shadow list is non-empty', () {
      expect(AppColors.SH, isNotEmpty);
    });

    test('SH_INSET shadow list is non-empty', () {
      expect(AppColors.SH_INSET, isNotEmpty);
    });
  });
}
